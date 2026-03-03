import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import infra/alias.{type BotContext}
import infra/api_calls
import infra/args
import infra/helpers
import infra/log
import infra/reply.{reply}
import infra/storage.{Array, String}
import models/error.{type BotError}
import telega
import telega/keyboard
import telega/update.{type Command, type Update}

pub fn command(ctx: BotContext, cmd: Command) -> Result(BotContext, BotError) {
  case ctx.update {
    update.CommandUpdate(message:, ..) -> {
      let replied_user =
        message.reply_to_message
        |> option.map(fn(msg) { msg.from })
        |> option.flatten

      let first_arg =
        args.try_parse_str(cmd.text, 1)
        |> option.then(fn(x) { Some(string.lowercase(x)) })

      case first_arg, replied_user {
        //when admin replied to user
        _, Some(user) -> {
          let lang_code = user.language_code |> option.unwrap("")
          use <- bool.lazy_guard(
            user.language_code |> option.is_none || lang_code == "",
            fn() { Ok(ctx) },
          )
          handle(ctx, lang_code)
        }
        //when admin provided lang_code as argument
        Some(lang_code), _ -> {
          let is_valid_input =
            ctx.session.resources.lang_codes
            |> list.find(fn(lang) {
              lang.0 == lang_code
              || string.lowercase(lang.1) == string.lowercase(lang_code)
            })

          case is_valid_input {
            Error(_) -> {
              use _ <- result.try(reply(
                ctx,
                log.format(
                  "Error: language code {0} not found. \nValid codes list: {1}",
                  [
                    lang_code,
                    ctx.session.resources.lang_codes
                      |> list.map(fn(x) { log.format("{0} ({1})", [x.0, x.1]) })
                      |> string.join(", "),
                  ],
                ),
              ))

              Ok(ctx)
            }
            Ok(lc) -> {
              handle(ctx, lc.0)
            }
          }
        }
        _, _ -> Ok(ctx)
      }
    }
    _ -> Ok(ctx)
  }
}

fn handle(ctx: BotContext, lang_code: String) {
  let already_exists =
    ctx.session.chat_settings.banned_lang_codes
    |> list.contains(lang_code)

  use <- bool.lazy_guard(already_exists, fn() {
    let new_codes =
      ctx.session.chat_settings.banned_lang_codes
      |> list.filter(fn(x) { x != lang_code })
      |> list.unique

    use _ <- result.try(storage.save_chat_property(
      ctx.session.db,
      ctx.update.chat_id,
      "banned_lang_codes",
      Array(new_codes |> list.map(fn(x) { String(x) })),
    ))
    use _ <- result.try(reply(
      ctx,
      log.format("Language {0} ({1}) is NOT banned anymore.", [
        lang_code,
        helpers.lookup_lang(ctx, lang_code),
      ]),
    ))

    Ok(ctx)
  })

  let cb_data = keyboard.bool_callback_data("next")
  let kb = build_kb(cb_data)
  let assert Ok(filter) = keyboard.filter_inline_keyboard_query(kb)

  let assert Ok(rm) =
    reply.reply_markup(
      ctx,
      log.format("Confirm you want to ban ALL {0} ({1}) users?", [
        lang_code,
        helpers.lookup_lang(ctx, lang_code),
      ]),
      keyboard.to_inline_markup(kb),
    )

  use ctx, payload, callback_query_id <- telega.wait_callback_query(
    ctx:,
    filter: Some(filter),
    or: option.None,
    timeout: Some(60),
  )

  let assert Ok(unpacked) = keyboard.unpack_callback(payload, cb_data)
  case unpacked.data {
    False -> {
      use _ <- result.try(api_calls.get_rid_of_msg(ctx, rm.message_id))
      Ok(ctx)
    }
    True -> {
      let new_codes =
        ctx.session.chat_settings.banned_lang_codes
        |> list.append([lang_code])
        |> list.unique

      use _ <- result.try(storage.save_chat_property(
        ctx.session.db,
        ctx.update.chat_id,
        "banned_lang_codes",
        Array(new_codes |> list.map(fn(x) { String(x) })),
      ))
      use _ <- result.try(reply.answer_callback(ctx, callback_query_id))
      use _ <- result.try(api_calls.get_rid_of_msg(ctx, rm.message_id))
      use _ <- result.try(reply(
        ctx,
        log.format("New banned languages list: {0}", [
          string.join(new_codes, ", "),
        ]),
      ))

      Ok(ctx)
    }
  }
}

fn build_kb(cb_data: keyboard.KeyboardCallbackData(Bool)) {
  let assert Ok(kb) = {
    let build = keyboard.inline_builder()
    use kb <- result.try(keyboard.inline_text(
      build,
      "Yes",
      keyboard.pack_callback(cb_data, True),
    ))
    use kb <- result.try(keyboard.inline_text(
      kb,
      "No",
      keyboard.pack_callback(cb_data, False),
    ))
    use kb <- result.try(keyboard.inline_text(
      kb,
      "Cancel",
      keyboard.pack_callback(cb_data, False),
    ))

    Ok(keyboard.inline_build(kb))
  }
  kb
}

pub fn checker(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
) -> Nil {
  case upd {
    update.AudioUpdate(message:, ..)
    | update.BusinessMessageUpdate(message:, ..)
    | update.EditedMessageUpdate(message:, ..)
    | update.PhotoUpdate(message:, ..)
    | update.TextUpdate(message:, ..)
    | update.VideoUpdate(message:, ..)
    | update.VoiceUpdate(message:, ..) -> {
      let lang_code =
        message.from
        |> option.then(fn(x) { x.language_code })

      let should_delete =
        lang_code
        |> option.map(fn(x) {
          ctx.session.chat_settings.banned_lang_codes |> list.contains(x)
        })
        |> option.unwrap(False)

      use <- bool.lazy_guard(!should_delete, fn() { next(ctx, upd) })

      log.printf(
        "Delete message from user: {0} id: {1}. Reason: banned language code: {2}",
        [
          helpers.try_get_fullname(message.from),
          upd.from_id |> int.to_string,
          lang_code |> option.unwrap(""),
        ],
      )
      api_calls.get_rid_of_msg(ctx, message.message_id)
      |> result.map(fn(_) { Nil })
      |> result.lazy_unwrap(fn() { next(ctx, upd) })
    }
    _ -> next(ctx, upd)
  }
}
