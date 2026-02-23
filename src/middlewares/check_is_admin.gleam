import gleam/bool
import gleam/list
import gleam/option
import infra/alias.{type BotContext}
import telega/update

pub fn check_is_admin() {
  fn(next) {
    fn(ctx: BotContext, upd: update.Update) {
      case upd {
        update.CommandUpdate(..) -> {
          let is_private_chat = upd.chat_id > 0

          let is_admin =
            ctx.session.chat_settings.admins_id_list
            |> option.unwrap([])
            |> list.filter(fn(id) { id == upd.from_id })
            |> list.is_empty
            |> bool.negate

          case is_private_chat || is_admin {
            False -> Ok(ctx)
            True -> next(ctx, upd)
          }
        }
        _ -> next(ctx, upd)
      }
    }
  }
}
