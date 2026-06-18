import gleam/bool
import gleam/json
import gleam/option.{None, Some}
import gleam/result
import gleam/string
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
        update.AudioUpdate(message:, ..)
        | update.TextUpdate(message:, ..)
        | update.VideoUpdate(message:, ..)
        | update.VoiceUpdate(message:, ..)
        | update.PhotoUpdate(message:, ..)
        | update.MessageUpdate(message:, ..)
        | update.WebAppUpdate(message:, ..)
        | update.EditedMessageUpdate(message:, ..) -> {
          let is_on_quarantine = case ctx.session.user_chat {
            Some(uc) -> uc.on_quarantine
            None -> False
          }

          use <- bool.lazy_guard(
            !is_on_quarantine || !ctx.session.is_trusted_sender,
            fn() { next(ctx, upd) },
          )

          let _ =
            uc_repo.save_user_chat_property(
              ctx.session.db,
              upd.from_id,
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
                helpers.view_sender(message),
              ])
            })
            |> result.map_error(fn(err) {
              log.printf_err(
                "Error occured on newcomers_events.save_user_chat_property. {0}",
                [err |> string.inspect],
              )
              err
            })

          next(ctx, upd)
        }
        ChatMemberUpdate(chat_member_updated:, chat_id:, ..) -> {
          //when user joins, put him to "quarantine"
          //write joined time
          case
            chat_member_updated.old_chat_member,
            chat_member_updated.new_chat_member
          {
            ChatMemberLeftChatMember(_), ChatMemberMemberChatMember(m) -> {
              use <- bool.lazy_guard(ctx.session.is_trusted_sender, fn() {
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
