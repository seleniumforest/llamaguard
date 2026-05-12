import gleam/bool
import gleam/result
import infra/alias
import infra/helpers
import infra/log
import infra/storage/user_chat as uc_repo
import models/user_chat
import telega/model/types.{
  ChatMemberBannedChatMember, ChatMemberLeftChatMember,
  ChatMemberMemberChatMember,
}
import telega/update.{ChatMemberUpdate}

//part of "strict_mode_newcomers" feature. catches events which could not be catched in main handler
pub fn newcomers_events() {
  fn(next) {
    fn(ctx: alias.BotContext, upd: update.Update) {
      case upd {
        ChatMemberUpdate(chat_member_updated:, chat_id:, ..) -> {
          //when user joins, put him to "quarantine"
          //write joined time
          case
            chat_member_updated.old_chat_member,
            chat_member_updated.new_chat_member
          {
            ChatMemberLeftChatMember(_), ChatMemberMemberChatMember(m) -> {
              let is_trusted =
                helpers.is_trusted_id(
                  ctx.session.chat_settings.trusted_users,
                  m.user.id,
                  m.user.username,
                  ctx.session.chat_settings.linked_channel_id.value,
                )

              use <- bool.lazy_guard(is_trusted, fn() {
                log.printf(
                  "Ctx: {0} User {1} has entered the chat, he's trusted, no need to quarantine him.",
                  [
                    helpers.view_chat(chat_member_updated.chat),
                    helpers.view_user(m.user),
                  ],
                )

                next(ctx, upd)
              })

              uc_repo.create_user_chat(
                ctx.session.db,
                m.user.id,
                upd.chat_id,
                user_chat.UserChat(
                  joined_time: helpers.now(),
                  messages: 0,
                  on_quarantine: True,
                ),
              )
              |> result.map(fn(_created) {
                log.printf(
                  "Ctx: {0} User {1} has entered the chat, putting him on quarantine.",
                  [
                    helpers.view_chat(chat_member_updated.chat),
                    helpers.view_user(m.user),
                  ],
                )
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
              })

              next(ctx, upd)
            }
            ChatMemberMemberChatMember(_), ChatMemberBannedChatMember(banned) -> {
              let _ =
                uc_repo.delete_user_chat(
                  ctx.session.db,
                  banned.user.id,
                  chat_id,
                )

              next(ctx, upd)
            }
            _, _ -> next(ctx, upd)
          }
        }
        _ -> next(ctx, upd)
      }
    }
  }
}
