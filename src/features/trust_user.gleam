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

pub fn checker(
  ctx: BotContext,
  upd: update.Update,
  next: fn(BotContext, update.Update) -> Nil,
) -> Nil {
  case ctx.session.is_trusted_sender {
    True -> Nil
    False -> next(ctx, upd)
  }
}
// pub fn checker(
//   ctx: BotContext,
//   upd: update.Update,
//   next: fn(BotContext, update.Update) -> Nil,
// ) -> Nil {
//   use <- bool.lazy_guard(!ctx.session.is_trusted_sender, fn() { next(ctx, upd) })

//   case upd {
//     update.AudioUpdate(message:, ..)
//     | update.TextUpdate(message:, ..)
//     | update.VideoUpdate(message:, ..)
//     | update.VoiceUpdate(message:, ..)
//     | update.PhotoUpdate(message:, ..)
//     | update.MessageUpdate(message:, ..)
//     | update.WebAppUpdate(message:, ..)
//     | update.EditedMessageUpdate(message:, ..) -> {
//       //Get user off from quarantine on first message AFTER he was trusted. 
//       //We cannot do it in command /trustuser @username because we don't know his ID from command args
//       //and that's kind of unreliable to memoize @username because it could be changed
//       let is_on_quarantine = case ctx.session.user_chat {
//         Some(uc) -> uc.on_quarantine
//         None -> False
//       }

//       use <- bool.guard(!is_on_quarantine, Nil)

//       uc_repo.save_user_chat_property(
//         ctx.session.db,
//         upd.from_id,
//         upd.chat_id,
//         ["on_quarantine"],
//         json.bool(False),
//       )
//       |> result.map(fn(is_found_and_updated) {
//         case is_found_and_updated {
//           True ->
//             log.printf(
//               "Ctx: {0} Sender {1} appeared on trust list, trying to un-quarantine him",
//               [helpers.view_chat(message.chat), helpers.view_sender(message)],
//             )
//           False ->
//             log.printf(
//               "Ctx: {0} Sender {1} is on trust list, tried to un-quarantine him, "
//                 <> "but haven't found his record. Some shit may happened",
//               [helpers.view_chat(message.chat), helpers.view_sender(message)],
//             )
//         }
//       })
//       |> result.unwrap(Nil)
//     }
//     update.ChatMemberUpdate(chat_member_updated:, ..) -> {
//       case chat_member_updated.new_chat_member {
//         types.ChatMemberMemberChatMember(member) -> {
//           use <- bool.lazy_guard(!ctx.session.is_trusted_sender, fn() {
//             next(ctx, upd)
//           })

//           //see first comment 
//           uc_repo.save_user_chat_property(
//             ctx.session.db,
//             member.user.id,
//             upd.chat_id,
//             ["on_quarantine"],
//             json.bool(False),
//           )
//           |> result.map(fn(found_and_updated) {
//             use <- bool.guard(!found_and_updated, Nil)
//             log.printf(
//               "Ctx: {0} User {1} has entered the chat, he's on trust list, no need to quarantine him.",
//               [
//                 helpers.view_chat(chat_member_updated.chat),
//                 helpers.view_user(member.user),
//               ],
//             )
//           })
//           |> result.unwrap(Nil)
//         }
//         _ -> next(ctx, upd)
//       }
//     }
//     _ -> next(ctx, upd)
//   }
// }
