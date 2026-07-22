import gleam/bool
import gleam/string
import infra/alias.{type BotContext}
import infra/cache_validation
import infra/log
import telega/model/types.{ChatMemberAdministratorChatMember}
import telega/update.{type Update, ChatMemberUpdate}

pub fn revalidate_new_admins() {
  fn(next) {
    fn(ctx: BotContext, update: Update) {
      case update {
        ChatMemberUpdate(chat_member_updated:, ..) -> {
          case chat_member_updated.new_chat_member {
            ChatMemberAdministratorChatMember(_m) -> {
              let #(new_ctx, errors) =
                cache_validation.validate_one(
                  ctx,
                  cache_validation.validate_admin_list,
                )

              use <- bool.lazy_guard(errors == [], fn() {
                next(new_ctx, update)
              })

              log.printf_err(
                "WARN: i see user was qualified to an administrator, but i could not get new admins list. Processing with old admins list. ERR: {0}",
                [errors |> string.inspect],
              )

              next(ctx, update)
            }
            _ -> next(ctx, update)
          }
        }
        _ -> next(ctx, update)
      }
    }
  }
}
