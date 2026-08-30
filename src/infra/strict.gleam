import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp
import gleam/result
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

const unnatural_symbols = ["–", "—", "₽", "€", "¥", "«", "»", "_bot", "•", "●"]

fn has_unnatural_symbols(str: option.Option(String)) {
  case str {
    Some(text) ->
      list.any(unnatural_symbols, fn(sym) { string.contains(text, sym) })
    None -> False
  }
}

const zero_lookalikes = ["O", "o", "О", "о"]

const numbers = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

fn check(number: List(String), zeros: List(String)) {
  let starts_with_num = int.parse(string.join(number, "")) |> result.is_ok
  use <- bool.guard(!starts_with_num, False)

  let continues_with_lookalike =
    zeros
    |> list.first()
    |> result.unwrap("")
    |> list.contains(["0", ..zero_lookalikes], _)
  use <- bool.guard(!continues_with_lookalike, False)

  let potential_replaces =
    list.filter(zeros, fn(z) { list.contains(zero_lookalikes, z) })

  use <- bool.guard(list.length(zeros) < 2, False)
  use <- bool.guard(potential_replaces == [], False)

  True
}

pub fn has_hidden_numbers(str: option.Option(String)) {
  case str {
    Some(text) -> {
      let text =
        text
        |> string.trim
        |> string.to_graphemes
        |> list.filter(fn(ch) { ch != " " })

      use <- bool.guard(list.length(text) < 2, False)

      //example: string "работа 5oOруб"
      let #(number, zeros, suffix) = {
        //split to ["работа ", "5oOруб"], throw away the prefix
        let #(_prefix, rest) =
          text
          |> list.split_while(fn(ch) { !list.contains(numbers, ch) })

        //separate number and the rest ["5", "oOруб"]
        let #(number, zeros) =
          list.split_while(rest, fn(ch) { list.contains(numbers, ch) })

        //separate potential zeros and the rest ["oO", "руб"]
        let #(zeros, suffix) =
          zeros
          |> list.split_while(fn(ch) {
            ch == "0" || list.contains(zero_lookalikes, ch)
          })

        #(number, zeros, suffix)
      }

      // log.printf("text: {0}, result: {1}", [
      //   string.join(text, ""),
      //   string.inspect(#(number, zeros, suffix)),
      // ])
      use <- bool.guard(number == [] || zeros == [], False)

      case check(number, zeros) {
        True -> True
        False if suffix != [] ->
          has_hidden_numbers(option.Some(string.join(suffix, "")))
        False -> False
      }
    }
    None -> False
  }
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
  let has_sus_guest_bot_call = msg.guest_bot_caller_user |> option.is_some
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

  let has_unnatural_symbols =
    has_unnatural_symbols(msg.text) || has_unnatural_symbols(msg.caption)

  let has_hidden_numbers =
    has_hidden_numbers(msg.text) || has_hidden_numbers(msg.caption)

  has_audio
  || has_photo
  || has_link
  || has_entities
  || has_caption_entities
  || has_video
  || has_video_note
  || has_game
  || has_document
  || has_sticker
  || has_emoji
  || has_quote
  || has_story
  || has_sus_guest_bot_call
  || has_shared_contact
  || has_shared_via_bot
  || has_unnatural_symbols
  || has_hidden_numbers
}
