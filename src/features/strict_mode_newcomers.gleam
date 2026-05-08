import gleam/bool
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import infra/alias.{type BotContext}
import infra/api_calls
import infra/args
import infra/helpers
import infra/log
import infra/reply.{reply, replyf}
import infra/storage/chat_settings as cs_storage
import infra/storage/user_chat as uc_repo
import models/error.{type BotError}
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
        ["strict_mode_newcomers"],
        json.int(arg),
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
            ["strict_mode_newcomers"],
            json.int(0),
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

  case upd {
    TextUpdate(message:, ..)
    | AudioUpdate(message:, ..)
    | MessageUpdate(message:, ..)
    | EditedMessageUpdate(message:, ..)
    | PhotoUpdate(message:, ..)
    | VideoUpdate(message:, ..)
    | VoiceUpdate(message:, ..) -> {
      let is_user_join_or_leave_system_msg = case
        message.left_chat_member,
        message.new_chat_members
      {
        Some(_), None -> True
        None, Some(users) -> users |> list.length > 0
        _, _ -> False
      }

      use <- bool.lazy_guard(is_user_join_or_leave_system_msg, fn() {
        next(ctx, upd)
      })

      case message.from {
        Some(from) -> handle_user(ctx, upd, next, message, from)
        _ -> next(ctx, upd)
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
      use <- bool.lazy_guard(!uc.on_quarantine, fn() { next(ctx, upd) })

      // let is_trusted_sender =
      //   helpers.is_trusted(
      //     ctx.session.chat_settings.trusted_users,
      //     upd.from_id,
      //     from.username,
      //   )

      // let enough_messages =
      //   uc.messages >= ctx.session.chat_settings.strict_mode_newcomers

      // use <- bool.lazy_guard(is_trusted_sender || enough_messages, fn() {
      //   //case when user was trusted AFTER joining and BEFORE passing quarantine
      //   uc_repo.save_user_chat_property(
      //     ctx.session.db,
      //     from.id,
      //     message.chat.id,
      //     ["on_quarantine"],
      //     json.bool(False),
      //   )
      //   |> result.map(fn(found_and_updated) {
      //     use <- bool.guard(!found_and_updated, Nil)
      //     log.printf(
      //       "Ctx: {0} User {1} is on trust list, no need to quarantine him",
      //       [],
      //     )
      //   })
      //   |> result.lazy_unwrap(fn() { next(ctx, upd) })
      // })

      let has_restricted = helpers.has_restricted_content(message)
      use <- bool.lazy_guard(!has_restricted, fn() {
        let nxt = next(ctx, upd)

        //update only after all checks
        let _ =
          uc_repo.save_user_chat_property(
            ctx.session.db,
            from.id,
            message.chat.id,
            ["messages"],
            json.int(uc.messages + 1),
          )

        nxt
      })

      log.printf("Ctx: {0} Ban {1} reason: did not passed quarantine", [
        helpers.view_chat(message.chat),
        helpers.view_user(from),
      ])

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
