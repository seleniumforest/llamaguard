import gleam/bool
import gleam/list
import gleam/option
import gleam/result
import infra/alias.{type BotContext}
import telega/api
import telega/model/types.{GetChatAdministratorsParameters, Int}
import telega/update

pub fn check_is_admin() {
  fn(handler) {
    fn(ctx: BotContext, upd: update.Update) {
      case upd {
        update.CommandUpdate(message:, ..) -> {
          let is_private = message.chat.type_ |> option.unwrap("") == "private"
          let continue_as_admin =
            is_private
            || api.get_chat_administrators(
              ctx.config.api_client,
              GetChatAdministratorsParameters(Int(upd.chat_id)),
            )
            |> result.unwrap([])
            |> list.filter(fn(el) {
              case el {
                types.ChatMemberAdministratorChatMember(admin) ->
                  admin.user.id == upd.from_id
                types.ChatMemberOwnerChatMember(owner) ->
                  owner.user.id == upd.from_id
                _ -> False
              }
            })
            |> list.is_empty
            |> bool.negate

          case continue_as_admin {
            False -> Ok(ctx)
            True -> handler(ctx, upd)
          }
        }
        _ -> handler(ctx, upd)
      }
    }
  }
}
