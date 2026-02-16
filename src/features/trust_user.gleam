import gleam/bool
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import infra/alias.{type BotContext}
import infra/args
import infra/helpers.{match_ids}
import infra/log
import infra/reply.{reply}
import infra/storage.{Array, String}
import models/error.{type BotError, GenericError}
import telega/model/types
import telega/update.{type Command}

pub fn command(ctx: BotContext, cmd: Command) -> Result(BotContext, BotError) {
  case args.try_parse_str(cmd.text, 1), ctx.update {
    option.Some(username), update.CommandUpdate(..) -> {
      handle_username(ctx, username)
    }
    option.None, update.CommandUpdate(message:, ..) -> {
      handle_reply(ctx, message)
    }
    _, _ -> no_username_reply(ctx)
  }
  |> result.try(fn(_) { Ok(ctx) })
}

fn no_username_reply(ctx: BotContext) {
  reply(
    ctx,
    "Please provide username with @ or make a reply to user with /trust",
  )
}

fn handle_username(
  ctx: BotContext,
  username: String,
) -> Result(types.Message, BotError) {
  case username {
    "@" <> u | "https://t.me/" <> u -> {
      process_id(ctx, "@" <> u)
    }
    _ -> Error(GenericError("Cannot extract username"))
  }
}

fn handle_reply(
  ctx: BotContext,
  message: types.Message,
) -> Result(types.Message, BotError) {
  let user_to_trust =
    message.reply_to_message
    |> option.map(fn(msg) { msg.from })
    |> option.flatten

  case user_to_trust {
    option.None -> no_username_reply(ctx)
    option.Some(user) -> {
      let str_id =
        user.id |> int.to_string
        <> case user.username {
          option.None -> ""
          option.Some(username) -> "@" <> username
        }

      process_id(ctx, str_id)
    }
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
    |> list.map(fn(x) { String(x) })

  storage.save_chat_property(
    ctx.session.db,
    ctx.update.chat_id,
    "trusted_users",
    Array(new_trusted_users),
  )
  |> result.try(fn(_) {
    let msg = case already_exists {
      True -> "User {0} is not trusted anymore"
      False -> "User {0} is trusted"
    }
    reply(ctx, log.format(msg, [id]))
  })
}
