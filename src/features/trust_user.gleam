import gleam/bool
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import infra/alias.{type BotContext}
import infra/args
import infra/helpers.{match_ids}
import infra/log
import infra/reply.{reply}
import infra/storage/chat_settings as cs_storage
import models/error.{type BotError}
import telega/model/types
import telega/update.{type Command}

//todo telegram sends some numbers as tel.numbers, needs fix
pub fn command(ctx: BotContext, cmd: Command) -> Result(BotContext, BotError) {
  case args.try_parse_str(cmd.text, 1), ctx.update {
    Some(username), update.CommandUpdate(..) -> {
      handle_username_or_id(ctx, username)
    }
    None, update.CommandUpdate(message:, ..) -> {
      handle_reply(ctx, message)
    }
    _, _ -> no_username_reply(ctx)
  }
  |> result.try(fn(_) { Ok(ctx) })
}

fn no_username_reply(ctx: BotContext) {
  reply(
    ctx,
    "Please provide either user's id OR username with @ or make a reply to user with /trustuser. Example: /trustuser @username",
  )
}

fn handle_username_or_id(
  ctx: BotContext,
  username: String,
) -> Result(types.Message, BotError) {
  case username {
    "@" <> u | "https://t.me/" <> u -> {
      process_id(ctx, "@" <> u)
    }
    _ ->
      case int.parse(username) {
        Ok(_) -> process_id(ctx, username)
        Error(_) -> no_username_reply(ctx)
      }
  }
}

fn handle_reply(
  ctx: BotContext,
  message: types.Message,
) -> Result(types.Message, BotError) {
  let user = case message.reply_to_message {
    Some(msg) -> {
      case msg.sender_chat, msg.from {
        Some(sc), _ -> {
          #(sc.id, sc.username) |> Some
        }
        _, Some(from) -> {
          #(from.id, from.username) |> Some
        }
        _, _ -> None
      }
    }
    None -> None
  }

  case user {
    Some(#(id, username)) -> {
      let joined =
        log.format("{0}{1}", [
          int.to_string(id),
          case username {
            None -> ""
            Some(u) -> "@" <> u
          },
        ])

      process_id(ctx, joined)
    }
    None -> no_username_reply(ctx)
  }
}

fn process_id(ctx: BotContext, id: String) {
  let already_exists =
    ctx.session.chat_settings.trusted_users
    |> list.any(fn(x) { match_ids(x, id) })

  let new_trusted_users =
    case already_exists {
      False ->
        ctx.session.chat_settings.trusted_users
        |> list.append([id])
      True ->
        ctx.session.chat_settings.trusted_users
        |> list.filter(fn(x) { match_ids(x, id) |> bool.negate })
    }
    |> list.unique

  let is_id = case int.parse(id) {
    Ok(_) -> True
    Error(_) -> False
  }

  cs_storage.save_chat_property(
    ctx.session.db,
    ctx.update.chat_id,
    ["trusted_users"],
    json.array(new_trusted_users, json.string),
  )
  |> result.try(fn(_) {
    let msg = case already_exists, is_id {
      True, True -> "User id {0} is not trusted anymore"
      True, False -> "Username {0} is not trusted anymore"
      False, True -> "User id {0} is trusted"
      False, False -> "Username {0} is trusted"
    }
    reply(ctx, log.format(msg, [id]))
  })
}
