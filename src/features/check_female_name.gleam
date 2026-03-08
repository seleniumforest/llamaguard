import gleam/bool
import gleam/int
import gleam/result
import infra/alias.{type BotContext}
import infra/api_calls
import infra/helpers
import infra/log
import models/error.{type BotError}
import telega/model/types
import telega/update.{type Command, type Update}

pub fn command(ctx: BotContext, _cmd: Command) -> Result(BotContext, BotError) {
  helpers.flip_bool_setting_and_reply(
    ctx,
    "check_female_name",
    fn(cs) { cs.check_female_name },
    "Success: bot will kick joining accounts with ENG/RU female name",
    "Success: bot will NOT kick joining accounts with ENG/RU female name",
  )
}

pub fn checker(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
) -> Nil {
  use <- bool.lazy_guard(!ctx.session.chat_settings.check_female_name, fn() {
    next(ctx, upd)
  })

  case upd {
    update.ChatMemberUpdate(chat_member_updated:, ..) -> {
      case chat_member_updated.new_chat_member {
        types.ChatMemberMemberChatMember(member) -> {
          let fullname = helpers.get_fullname(member.user)
          let is_female_name = helpers.has_woman_name(ctx, fullname)

          use <- bool.lazy_guard(!is_female_name, fn() { next(ctx, upd) })

          log.printf("Ban user: {0} id: {1} reason: woman", [
            fullname,
            int.to_string(member.user.id),
          ])

          api_calls.get_rid_of_user(ctx, member.user.id)
          |> result.try(fn(_) { Ok(Nil) })
          |> result.lazy_unwrap(fn() { next(ctx, upd) })
        }
        _ -> next(ctx, upd)
      }
    }
    _ -> next(ctx, upd)
  }
}
