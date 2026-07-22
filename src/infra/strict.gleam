import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp
import gleam/string
import infra/ffi/unicode
import telega/model/types.{type Message, type MessageEntity}

pub fn has_woman_name(female_names: List(String), full_name: String) {
  use <- bool.guard(string.is_empty(full_name), False)

  let assert Ok(reg) = regexp.from_string("[\\p{P}\\p{S}\\p{Emoji}]")

  full_name
  |> unicode.normalize_nfkd
  |> string.lowercase
  |> regexp.replace(reg, _, "")
  |> string.split(" ")
  |> list.map(string.trim)
  |> list.any(fn(x) { !string.is_empty(x) && list.contains(female_names, x) })
}

const allowed_entities = ["phone_number", "date_time"]

fn filter_entities(entities: Option(List(MessageEntity))) {
  entities
  |> option.unwrap([])
  |> list.filter(fn(x) { !list.contains(allowed_entities, x.type_) })
  |> list.is_empty
  |> bool.negate
}

pub fn has_suspicious_content(msg: Message) -> Bool {
  let has_audio = msg.audio |> option.is_some
  let has_photo = msg.photo |> option.is_some
  let has_video = msg.video |> option.is_some
  let has_video_note = msg.video_note |> option.is_some
  let has_game = msg.game |> option.is_some
  let has_document = msg.document |> option.is_some
  let has_sticker = msg.sticker |> option.is_some
  let has_quote = msg.quote |> option.is_some
  let has_story = msg.story |> option.is_some
  let has_shared_contact = msg.contact |> option.is_some
  let has_shared_via_bot = msg.via_bot |> option.is_some
  let has_guest_bot = msg.guest_bot_caller_user |> option.is_some
  let has_caption_entities = filter_entities(msg.caption_entities)
  let has_entities = filter_entities(msg.entities)
  let has_link = case regexp.from_string("https?://\\S+"), msg.text {
    Ok(url_regex), Some(text) -> {
      regexp.scan(with: url_regex, content: text)
      |> list.is_empty
      |> bool.negate
    }
    _, _ -> False
  }
  let has_emoji = case msg.text {
    Some(text) ->
      case regexp.from_string("\\p{Extended_Pictographic}") {
        Ok(re) -> regexp.check(re, text)
        Error(_) -> False
      }
    None -> False
  }

  has_audio
  || has_photo
  || has_link
  || has_entities
  || has_video
  || has_video_note
  || has_game
  || has_document
  || has_sticker
  || has_caption_entities
  || has_emoji
  || has_quote
  || has_story
  || has_guest_bot
  || has_shared_contact
  || has_shared_via_bot
}
