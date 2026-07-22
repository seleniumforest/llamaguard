import gleam/bool
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import infra/alias
import infra/handle
import infra/helpers
import infra/log
import infra/storage/user_chat as uc_repo
import models/bot_session
import models/user_chat
import telega/bot
import telega/model/types.{
  ChatMemberBannedChatMember, ChatMemberLeftChatMember,
  ChatMemberMemberChatMember,
}
import telega/update

pub fn newcomers_events() {
  fn(next) {
    fn(ctx: alias.BotContext, upd: update.Update) {
      let lazynext = fn() { next(ctx, upd) }
      handle.upd(
        upd,
        fn(message) {
          use uc <- handle.userchat(ctx, lazynext)
          use <- bool.lazy_guard(!uc.on_quarantine, lazynext)

          message.text
          |> option.then(fn(text) {
            let _ =
              uc_repo.save_user_chat_property(
                ctx.session.db,
                ctx.session.real_sender.0,
                upd.chat_id,
                ["messages"],
                json.array(
                  [
                    user_chat.UserMessage(message.message_id, text),
                    ..list.filter(uc.messages, fn(m) {
                      m.id != message.message_id
                    })
                  ],
                  user_chat.message_encoder,
                ),
              )

            Some(text)
          })

          use <- bool.lazy_guard(!ctx.session.is_trusted_sender, lazynext)

          let _ =
            uc_repo.save_user_chat_property(
              ctx.session.db,
              ctx.session.real_sender.0,
              upd.chat_id,
              ["on_quarantine"],
              json.bool(False),
            )
            |> result.map(fn(is_found_and_updated) {
              case is_found_and_updated {
                True ->
                  "Ctx: {0} Sender {1} appeared on trust list, trying to un-quarantine him"
                False ->
                  "Ctx: {0} Sender {1} is on trust list, tried to un-quarantine him, "
                  <> "but haven't found his record. Some shit may happened"
              }
              |> log.printf([
                helpers.view_chat(message.chat),
                handle.view_sender(message),
              ])
            })
            |> result.map_error(fn(err) {
              log.printf_err(
                "Error occured on newcomers_events.save_user_chat_property. {0}",
                [err |> string.inspect],
              )
              err
            })

          lazynext()
        },
        fn(chat_member_updated) {
          //when user joins, put him to "quarantine"
          //write joined time
          case
            chat_member_updated.old_chat_member,
            chat_member_updated.new_chat_member
          {
            ChatMemberLeftChatMember(_), ChatMemberMemberChatMember(m) -> {
              use <- bool.lazy_guard(
                ctx.session.chat_settings.strict_mode_newcomers <= 0,
                lazynext,
              )

              use <- bool.lazy_guard(ctx.session.is_trusted_sender, fn() {
                log.printf(
                  "Ctx: {0} User {1} has entered the chat, he's trusted, no need to quarantine him.",
                  [
                    helpers.view_chat(chat_member_updated.chat),
                    helpers.view_user(m.user),
                  ],
                )

                lazynext()
              })

              let new_ctx =
                uc_repo.create_user_chat(
                  ctx.session.db,
                  m.user.id,
                  upd.chat_id,
                  user_chat.UserChat(
                    joined_time: helpers.now(),
                    messages: [],
                    on_quarantine: True,
                    first_name: m.user.first_name,
                    last_name: m.user.last_name |> option.unwrap(""),
                  ),
                )
                |> result.map(fn(created) {
                  log.printf(
                    "Ctx: {0} User {1} has entered the chat, putting him on quarantine.",
                    [
                      helpers.view_chat(chat_member_updated.chat),
                      helpers.view_user(m.user),
                    ],
                  )

                  let session =
                    bot_session.BotSession(
                      ..ctx.session,
                      user_chat: Some(created),
                    )

                  bot.Context(..ctx, session:)
                })
                |> result.lazy_unwrap(fn() {
                  log.printf(
                    "WARN: Ctx: {0} User {1} has entered the chat, couldn't put him on quarantine. "
                      <> "Some shit happened, please check",
                    [
                      helpers.view_chat(chat_member_updated.chat),
                      helpers.view_user(m.user),
                    ],
                  )

                  ctx
                })

              next(new_ctx, upd)
            }
            ChatMemberMemberChatMember(_), ChatMemberBannedChatMember(banned) -> {
              clean_user_chat(ctx, upd, banned.user, chat_member_updated, next)
            }
            ChatMemberMemberChatMember(_), ChatMemberLeftChatMember(left) -> {
              clean_user_chat(ctx, upd, left.user, chat_member_updated, next)
            }
            _, _ -> lazynext()
          }
        },
        fn(_) { lazynext() },
        lazynext,
      )
    }
  }
}

fn clean_user_chat(
  ctx: alias.BotContext,
  upd,
  user: types.User,
  chat_member_updated: types.ChatMemberUpdated,
  next,
) {
  uc_repo.delete_user_chat(ctx.session.db, user.id, chat_member_updated.chat.id)
  |> result.map(fn(is_deleted) {
    case is_deleted {
      True -> bot_session.BotSession(..ctx.session, user_chat: None)
      False -> ctx.session
    }
  })
  |> result.try(fn(session) { next(bot.Context(..ctx, session:), upd) })
}
