import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import infra/alias.{type BotContext}
import infra/api_calls
import infra/args
import infra/helpers
import infra/log
import infra/reply.{reply, replyf}
import infra/storage/chat_settings as cs_storage
import infra/storage/kvstorage.{Bool, Int, Value}
import infra/storage/user_chat as uc_repo
import models/error.{type BotError}
import models/user_chat
import telega/model/types
import telega/update.{
  type Command, type Update, AudioUpdate, EditedMessageUpdate, MessageUpdate,
  PhotoUpdate, TextUpdate, VideoUpdate, VoiceUpdate,
}

pub fn command(ctx: BotContext, cmd: Command) -> Result(BotContext, BotError) {
  let args_count = args.args_count(cmd.text)

  case args.try_parse_int(cmd.text, 1) {
    Some(arg) -> {
      use _ <- result.try(cs_storage.save_chat_property(
        ctx.session.db,
        ctx.update.chat_id,
        "strict_mode_newcomers",
        Value(Int(arg)),
      ))

      case arg {
        a if a > 0 ->
          replyf(
            ctx,
            "Success: strict mode (no media, links, reactions, female name) for first {0} messages is enabled",
            [arg |> int.to_string()],
          )
        0 -> reply(ctx, "Success: strict mode for non-members disabled")
        _ -> reply(ctx, "Error: argument must be positive")
      }
    }
    None -> {
      case ctx.session.chat_settings.strict_mode_newcomers {
        smn if smn > 0 && args_count == 0 -> {
          use _ <- result.try(cs_storage.save_chat_property(
            ctx.session.db,
            ctx.update.chat_id,
            "strict_mode_newcomers",
            Value(Int(0)),
          ))

          reply(ctx, "Success: strict mode for non-members disabled")
        }
        _ -> reply(ctx, "Usage: /strictModeNewcomers <no_of_msgs>")
      }
    }
  }
  |> result.try(fn(_) { Ok(ctx) })
}

pub fn checker(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
) -> Nil {
  use <- bool.lazy_guard(
    ctx.session.chat_settings.strict_mode_newcomers <= 0,
    fn() { next(ctx, upd) },
  )

  echo "strict_mode_newcomers = "
    <> ctx.session.chat_settings.strict_mode_newcomers |> string.inspect

  case upd {
    TextUpdate(message:, ..)
    | AudioUpdate(message:, ..)
    | MessageUpdate(message:, ..)
    | EditedMessageUpdate(message:, ..)
    | PhotoUpdate(message:, ..)
    | VideoUpdate(message:, ..)
    | VoiceUpdate(message:, ..) -> {
      let is_user_join_system_msg = case message.new_chat_members {
        Some(users) -> users |> list.length > 0
        None -> False
      }

      use <- bool.lazy_guard(is_user_join_system_msg, fn() {
        echo "skipping system join msg"
        next(ctx, upd)
      })

      case message.sender_chat, message.from {
        Some(sc), _ -> handle_chat(ctx, upd, next, message, sc)
        _, Some(from) -> handle_user(ctx, upd, next, message, from)
        _, _ -> next(ctx, upd)
      }
    }

    _ -> next(ctx, upd)
  }
}

fn handle_user(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
  message: types.Message,
  from: types.User,
) -> Nil {
  let userchat = uc_repo.get_user_chat(ctx.session.db, from.id, message.chat.id)
  case userchat {
    Ok(uc) -> {
      echo "userchat: " <> uc |> string.inspect

      use <- bool.lazy_guard(!uc.on_quarantine, fn() {
        echo "user is not on quarantine"
        next(ctx, upd)
      })

      use <- bool.lazy_guard(
        uc.messages >= ctx.session.chat_settings.strict_mode_newcomers,
        fn() {
          let _ =
            uc_repo.save_user_chat_property(
              ctx.session.db,
              from.id,
              message.chat.id,
              "on_quarantine",
              False |> Bool |> Value,
            )
          next(ctx, upd)
        },
      )

      let has_restricted = helpers.has_restricted_content(message)
      use <- bool.lazy_guard(!has_restricted, fn() {
        echo "user has" <> uc.messages + 1 |> string.inspect <> "messages"
        let _ =
          uc_repo.save_user_chat_property(
            ctx.session.db,
            from.id,
            message.chat.id,
            "messages",
            uc.messages + 1 |> Int |> Value,
          )
        next(ctx, upd)
      })

      echo "restricted content during quarantine"

      let _ =
        uc_repo.delete_user_chat(ctx.session.db, from.id, message.chat.id)
        |> result.try(fn(_) {
          api_calls.get_rid_of_msg(ctx, message.message_id)
        })
        |> result.try(fn(_) { api_calls.get_rid_of_user(ctx, from.id) })

      Nil
    }
    Error(_) -> next(ctx, upd)
  }
}

fn handle_chat(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
  message: types.Message,
  sc: types.Chat,
) -> Nil {
  echo "as sender_chat"
  //we cannot detect "join" event for sender_chat, so create record when the first msg appeared
  let userchat =
    uc_repo.get_user_chat(ctx.session.db, sc.id, message.chat.id)
    |> result.try_recover(fn(err) {
      case err {
        error.EmptyDataError -> {
          uc_repo.create_user_chat(
            ctx.session.db,
            sc.id,
            message.chat.id,
            user_chat.UserChat(
              joined_time: helpers.now(),
              messages: 0,
              on_quarantine: True,
            ),
          )
        }
        _ -> Error(err)
      }
    })

  case userchat {
    Ok(uc) -> {
      echo "userchat: " <> uc |> string.inspect

      use <- bool.lazy_guard(!uc.on_quarantine, fn() {
        echo "chat is not on quarantine"
        next(ctx, upd)
      })

      use <- bool.lazy_guard(
        uc.messages >= ctx.session.chat_settings.strict_mode_newcomers,
        fn() {
          let _ =
            uc_repo.save_user_chat_property(
              ctx.session.db,
              sc.id,
              message.chat.id,
              "on_quarantine",
              False |> Bool |> Value,
            )
          next(ctx, upd)
        },
      )

      let has_restricted = helpers.has_restricted_content(message)
      use <- bool.lazy_guard(!has_restricted, fn() {
        echo "chat has" <> uc.messages + 1 |> string.inspect <> "messages"
        let _ =
          uc_repo.save_user_chat_property(
            ctx.session.db,
            sc.id,
            message.chat.id,
            "messages",
            uc.messages + 1 |> Int |> Value,
          )
        next(ctx, upd)
      })

      log.printf("Ban chat: {0} id: {1} reason: did not passed quarantine", [
        sc.title |> option.unwrap(""),
        sc.id |> int.to_string,
      ])

      let _ =
        uc_repo.delete_user_chat(ctx.session.db, sc.id, message.chat.id)
        |> result.try(fn(_) {
          api_calls.get_rid_of_msg(ctx, message.message_id)
        })
        |> result.try(fn(_) { api_calls.get_rid_of_chat(ctx, sc) })

      Nil
    }
    Error(_) -> next(ctx, upd)
  }
}
