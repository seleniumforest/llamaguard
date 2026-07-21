import gleam/bool
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import infra/alias.{type BotContext}
import infra/api_calls
import infra/handle
import infra/helpers
import models/bot_session.{BotSession}
import telega/bot.{Context}
import telega/model/types
import telega/update

pub fn setup_flags() {
  fn(next) {
    fn(ctx: BotContext, upd: update.Update) {
      let cs = ctx.session.chat_settings
      let is_private_chat = upd.chat_id > 0

      let assert Ok(real_sender) = handle.get_real_sender_by_upd(upd)

      let is_admin =
        cs.admins_list.value
        |> list.contains(real_sender.0)

      let is_linked_channel = cs.linked_channel_id.value == real_sender.0

      let is_trusted =
        ctx.session.chat_settings.trusted_users
        |> list.any(fn(id) {
          helpers.match_ids(id, helpers.join_id(real_sender))
        })

      let is_sender_on_quarantine = case ctx.session.user_chat {
        Some(uc) -> uc.on_quarantine
        None -> False
      }

      //WARN: this flag only needed when checking anon reactions 
      //and comments under linked channel's posts
      let is_sender_non_member = fn() {
        let make_call = fn(chat_id) {
          api_calls.get_chat_member(ctx, chat_id, real_sender.0)
          |> result.map(fn(cm) {
            case cm {
              types.ChatMemberRestrictedChatMember(_)
              | types.ChatMemberLeftChatMember(_)
              | types.ChatMemberBannedChatMember(_) -> True
              _ -> False
            }
          })
          |> result.unwrap(False)
        }

        handle.upd(
          upd,
          fn(message) {
            use reply <- helpers.option_guard(message.reply_to_message, False)
            use origin <- helpers.option_guard(reply.forward_origin, False)
            use <- bool.guard(cs.linked_channel_id.value == 0, False)

            case origin {
              types.MessageOriginChannelMessageOrigin(origin) -> {
                case origin.chat.id == cs.linked_channel_id.value {
                  True -> make_call(message.chat.id)
                  False -> False
                }
              }
              _ -> False
            }
          },
          fn(_chat_member_updated) { False },
          fn(message_reaction_updated) {
            make_call(message_reaction_updated.chat.id)
          },
          fn() { False },
        )
      }

      let ctx =
        Context(
          ..ctx,
          session: BotSession(
            ..ctx.session,
            is_admin:,
            is_trusted_sender: is_trusted || is_linked_channel || is_admin,
            is_private_chat:,
            real_sender:,
            is_sender_on_quarantine:,
            is_sender_non_member:,
            is_sender_a_chat: real_sender.0 < 0,
          ),
        )

      case upd {
        update.CommandUpdate(..) -> {
          case is_private_chat || is_admin {
            True -> next(ctx, upd)
            False -> Ok(ctx)
          }
        }
        _ -> next(ctx, upd)
      }
    }
  }
}
