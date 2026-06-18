import gleam/list
import infra/alias.{type BotContext}
import infra/helpers
import models/bot_session.{BotSession}
import telega/bot.{Context}
import telega/update

pub fn setup_permissions() {
  fn(next) {
    fn(ctx: BotContext, upd: update.Update) {
      let is_private_chat = upd.chat_id > 0

      let real_sender = helpers.get_real_sender_by_upd(upd)

      let is_admin =
        ctx.session.chat_settings.admins_list.value
        |> list.contains(real_sender.0)

      let is_linked_channel =
        ctx.session.chat_settings.linked_channel_id.value == real_sender.0

      let is_trusted =
        ctx.session.chat_settings.trusted_users
        |> list.any(fn(id) {
          helpers.match_ids(id, helpers.join_id(real_sender))
        })

      let ctx =
        Context(
          ..ctx,
          session: BotSession(
            ..ctx.session,
            is_admin:,
            is_trusted_sender: is_trusted || is_linked_channel || is_admin,
            is_private_chat:,
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
