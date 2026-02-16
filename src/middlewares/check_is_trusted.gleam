import gleam/int
import gleam/list
import gleam/option
import infra/alias.{type BotContext}
import infra/helpers.{match_ids}
import telega/update

pub fn check_is_trusted() {
  fn(next) {
    fn(ctx: BotContext, upd: update.Update) {
      case upd {
        update.MessageUpdate(from_id:, message:, ..)
        | update.AudioUpdate(from_id:, message:, ..)
        | update.TextUpdate(from_id:, message:, ..)
        | update.VideoUpdate(from_id:, message:, ..)
        | update.VoiceUpdate(from_id:, message:, ..)
        | update.PhotoUpdate(from_id:, message:, ..)
        | update.EditedMessageUpdate(from_id:, message:, ..) -> {
          let id_to_match = from_id |> int.to_string
          let username_to_match =
            message.from
            |> option.map(fn(x) { x.username })
            |> option.flatten

          let is_trusted =
            ctx.session.chat_settings.trusted_users
            |> list.any(fn(x) {
              let match_by_id = match_ids(x, id_to_match)
              let match_by_username = case username_to_match {
                option.None -> False
                option.Some(u) -> match_ids(x, "@" <> u)
              }

              match_by_id || match_by_username
            })

          case is_trusted {
            False -> next(ctx, upd)
            True -> Ok(ctx)
          }
        }
        _ -> next(ctx, upd)
      }
    }
  }
}
