import gleam/bool
import gleam/string
import infra/alias.{type BotContext}
import infra/cache_validation
import infra/handle
import infra/log
import telega/model/types.{ChatMemberAdministratorChatMember}
import telega/update.{type Update}

pub fn revalidate_new_admins() {
  fn(next) {
    fn(ctx: BotContext, update: Update) {
      use chat_mem_upd <- handle.member_upd(update, fn() { next(ctx, update) })

      case chat_mem_upd.old_chat_member, chat_mem_upd.new_chat_member {
        _, ChatMemberAdministratorChatMember(_m)
        | ChatMemberAdministratorChatMember(_m), _
        -> {
          let #(new_ctx, errors) =
            cache_validation.validate_one(
              ctx,
              cache_validation.validate_admin_list,
            )

          use <- bool.lazy_guard(errors == [], fn() { next(new_ctx, update) })

          log.printf_err(
            "WARN: i see user was (dis)qualified to/from an administrator, but i could not get new admins list. Processing with old admins list. ERR: {0}",
            [errors |> string.inspect],
          )

          next(ctx, update)
        }
        _, _ -> next(ctx, update)
      }
    }
  }
}
