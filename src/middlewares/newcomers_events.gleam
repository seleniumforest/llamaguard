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
        ChatMemberUpdate(chat_member_updated:, chat_id:, ..) -> {
          //when user joins, put him to "quarantine"
          //write joined time
          echo "chatmemberupd"
          case
            chat_member_updated.old_chat_member,
            chat_member_updated.new_chat_member
          {
            ChatMemberLeftChatMember(_), ChatMemberMemberChatMember(m) -> {
              echo log.format(
                "User joined. Creating user_chat entry for new sender_chat id: {0} chat_id: {1}",
                [m.user.id |> string.inspect, chat_id |> string.inspect],
              )

              let _ =
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

              next(ctx, upd)
            }
            //types.ChatMemberRestrictedChatMember(_) -> todo
            ChatMemberMemberChatMember(_), ChatMemberBannedChatMember(banned) -> {
              echo "chatmember ban"
              echo log.format(
                "User banned. Removing user_chat entry user_id: {0} chat_id: {1}",
                [
                  banned.user.id |> string.inspect,
                  chat_id |> string.inspect,
                ],
              )

              let _ =
                uc_repo.delete_user_chat(
                  ctx.session.db,
                  banned.user.id,
                  chat_id,
                )
              next(ctx, upd)
            }
            _, _ -> {
              echo "fallback"
              next(ctx, upd)
            }
          }
        }
        _ -> next(ctx, upd)
      }
    }
  }
}
