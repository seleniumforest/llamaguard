import gleam/bool
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import infra/alias.{type BotContext}
import infra/helpers
import infra/log
import models/error.{type BotError}
import telega/api
import telega/model/types.{BanChatMemberParameters, Int}
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
  case upd, ctx.session.chat_settings.check_female_name {
    update.ChatMemberUpdate(chat_member_updated:, chat_id:, ..), True -> {
      case chat_member_updated.new_chat_member {
        types.ChatMemberMemberChatMember(member) -> {
          let first = member.user.first_name |> normalize
          let last =
            member.user.last_name
            |> option.unwrap("")
            |> normalize

          let is_female_name =
            ctx.session.resources.female_names
            |> list.filter(fn(x) { x == first || x == last })
            |> list.is_empty
            |> bool.negate

          use <- bool.lazy_guard(!is_female_name, fn() { next(ctx, upd) })

          log.printf("Ban user: {0} {1} id: {2} reason: woman", [
            member.user.first_name,
            member.user.last_name |> option.unwrap(""),
            int.to_string(member.user.id),
          ])

          api.ban_chat_member(
            ctx.config.api_client,
            parameters: BanChatMemberParameters(
              chat_id: Int(chat_id),
              user_id: member.user.id,
              until_date: option.None,
              revoke_messages: option.Some(True),
            ),
          )
          |> result.try(fn(_) { Ok(Nil) })
          |> result.lazy_unwrap(fn() { next(ctx, upd) })
        }
        _ -> next(ctx, upd)
      }
    }
    _, _ -> next(ctx, upd)
  }
}

fn normalize(name: String) {
  name
  |> string.lowercase()
  |> string.trim
}
