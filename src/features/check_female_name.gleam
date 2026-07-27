import gleam/bool
import gleam/option.{Some}
import gleam/result
import infra/alias.{type BotContext}
import infra/api_calls
import infra/cmd_utils
import infra/handle
import infra/helpers
import infra/log
import infra/strict
import models/error.{type BotError}
import telega/update.{type Command, type Update}

pub fn command(ctx: BotContext, _cmd: Command) -> Result(BotContext, BotError) {
  cmd_utils.flip_bool_setting_and_reply(
    ctx,
    ["check_female_name"],
    fn(cs) { cs.check_female_name },
    "Success: bot will ban accounts with ENG/RU female name when they join or put reactions.",
    "Success: bot will NOT ban accounts with ENG/RU female name anymore",
  )
}

pub fn checker(
  ctx: BotContext,
  upd: Update,
  next: fn(BotContext, Update) -> Nil,
) -> Nil {
  log.debug(ctx.dependencies.log, "check_female_name")
  let next = fn() { next(ctx, upd) }
  use <- bool.lazy_guard(!ctx.session.chat_settings.check_female_name, next)
  use <- handle.apply_to_targets(
    session: ctx.session,
    trusted_senders: False,
    non_members: True,
    newcomers: True,
    chatsenders: True,
    next:,
  )

  handle.upd(
    upd,
    fn(message) {
      handle.real_sender(
        message,
        fn(user) {
          let fullname = helpers.get_fullname(user)
          let is_female_name =
            strict.has_woman_name(ctx.session.resources.female_names, fullname)

          use <- bool.lazy_guard(!is_female_name, next)

          log.printf(
            "Ctx: {0} Ban {1} Filter: check_female_name Reason: woman",
            [
              helpers.view_chat(message.chat),
              helpers.view_user(user),
            ],
          )

          api_calls.get_rid_of_msg(ctx, message.message_id)
          |> result.try(fn(_) { api_calls.get_rid_of_usersender(ctx, user.id) })
          |> result.try(fn(_) { Ok(Nil) })
          |> result.lazy_unwrap(next)
        },
        fn(chatsender) {
          let is_female_name = case chatsender.title {
            Some(title) ->
              strict.has_woman_name(ctx.session.resources.female_names, title)
            option.None -> False
          }

          use <- bool.lazy_guard(!is_female_name, next)

          log.printf(
            "Ctx: {0} Ban {1} Filter: check_female_name Reason: woman",
            [
              helpers.view_chat(message.chat),
              helpers.view_chat(chatsender),
            ],
          )

          api_calls.get_rid_of_msg(ctx, message.message_id)
          |> result.try(fn(_) {
            api_calls.get_rid_of_chatsender(ctx, chatsender)
          })
          |> result.try(fn(_) { Ok(Nil) })
          |> result.lazy_unwrap(next)
        },
        fn() { next() },
      )
    },
    fn(join) {
      use user <- handle.joined_user(join, next)
      let fullname = helpers.get_fullname(user)
      let is_female_name =
        strict.has_woman_name(ctx.session.resources.female_names, fullname)

      use <- bool.lazy_guard(!is_female_name, next)

      log.printf("Ctx: {0} Ban {1} Filter: check_female_name Reason: woman", [
        helpers.view_chat(join.chat),
        helpers.view_user(user),
      ])

      api_calls.get_rid_of_usersender(ctx, user.id)
      |> result.try(fn(_) { Ok(Nil) })
      |> result.lazy_unwrap(next)
    },
    fn(reaction) {
      handle.reaction_sender(
        reaction,
        fn(user) {
          let fullname = helpers.get_fullname(user)
          let is_female_name =
            strict.has_woman_name(ctx.session.resources.female_names, fullname)

          use <- bool.lazy_guard(!is_female_name, next)

          log.printf(
            "Ctx: {0} Ban {1} Filter: check_female_name Reason: woman",
            [
              helpers.view_chat(reaction.chat),
              helpers.view_user(user),
            ],
          )

          api_calls.get_rid_of_usersender(ctx, user.id)
          |> result.try(fn(_) {
            api_calls.get_rid_of_usersender_reactions(
              ctx,
              reaction.chat.id,
              user.id,
            )
          })
          |> result.try(fn(_) { Ok(Nil) })
          |> result.lazy_unwrap(next)
        },
        fn(actor_chat) {
          let is_female_name =
            strict.has_woman_name(
              ctx.session.resources.female_names,
              actor_chat.title |> option.unwrap(""),
            )

          use <- bool.lazy_guard(!is_female_name, next)

          log.printf(
            "Ctx: {0} Ban {1} Filter: check_female_name Reason: woman",
            [
              helpers.view_chat(reaction.chat),
              helpers.view_chat(actor_chat),
            ],
          )

          api_calls.get_rid_of_chatsender(ctx, actor_chat)
          |> result.try(fn(_) {
            api_calls.get_rid_of_chatsender_reactions(
              ctx,
              reaction.chat.id,
              actor_chat.id,
            )
          })
          |> result.try(fn(_) { Ok(Nil) })
          |> result.lazy_unwrap(next)
        },
        next,
      )
    },
    next,
  )
}
