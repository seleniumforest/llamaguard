//Command utils, frequently used functions to handle commands from user
import gleam/bool
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import infra/alias.{type BotContext}
import infra/args
import infra/log
import infra/reply.{reply}
import infra/storage/chat_settings as cs_storage
import models/chat_settings.{type ChatSettings}
import models/error.{type BotError}
import telega/update.{type Command}

//handles bool argument
pub fn flip_bool_setting_and_reply(
  ctx: BotContext,
  setting_path: List(String),
  setting_selector: fn(ChatSettings) -> Bool,
  on_msg: String,
  off_msg: String,
) -> Result(BotContext, BotError) {
  let current_state = setting_selector(ctx.session.chat_settings)
  let new_state = !current_state

  use _ <- result.try(cs_storage.save_chat_property(
    ctx.session.db,
    ctx.update.chat_id,
    setting_path,
    json.bool(new_state),
  ))

  use _ <- result.try(
    reply(ctx, case new_state {
      False -> off_msg
      True -> on_msg
    }),
  )

  Ok(ctx)
}

const max_num_arg_value = 1_000_000_000_000

fn triplets(num: Int) {
  use <- bool.guard(num < 10_000, int.to_string(num))

  num
  |> int.to_string
  |> string.reverse
  |> string.to_graphemes
  |> list.sized_chunk(3)
  |> list.map(fn(triplet) { string.join(triplet, "") })
  |> string.join("_")
  |> string.reverse
}

//handles first positive number argument
pub fn handle_number_and_reply(
  ctx: BotContext,
  cmd: Command,
  setting_path: List(String),
  setting_selector: fn(ChatSettings) -> Int,
  updated_msg_pattern: String,
  turned_off_msg_pattern: String,
  usage_msg: String,
) {
  let args_count = args.args_count(cmd.text)
  let cur = setting_selector(ctx.session.chat_settings)

  let save_n_reply = fn(new_value: Int, pattern: String, display_val: Int) {
    cs_storage.save_chat_property(
      ctx.session.db,
      ctx.update.chat_id,
      setting_path,
      json.int(new_value),
    )
    |> result.try(fn(_) {
      reply(ctx, log.format(pattern, [triplets(display_val)]))
    })
  }

  case args.try_parse_int(cmd.text, 1) {
    Some(arg) -> {
      case arg {
        a if a > 0 && a < max_num_arg_value ->
          save_n_reply(a, updated_msg_pattern, a)
        0 -> save_n_reply(0, turned_off_msg_pattern, cur)
        _ -> reply(ctx, usage_msg)
      }
    }
    None -> {
      //when user has enabled feature, and provides no arguments - just turn it off
      case cur, args_count {
        cur, args_count if cur > 0 && args_count == 0 ->
          save_n_reply(0, turned_off_msg_pattern, cur)
        _, _ -> reply(ctx, usage_msg)
      }
    }
  }
  |> result.try(fn(_) { Ok(ctx) })
}

//handles array of unique case-insensetive strings
pub fn insert_or_delete_and_reply(
  ctx: BotContext,
  setting_path: List(String),
  setting_selector: fn(ChatSettings) -> List(String),
  new_value: String,
  inserted_msg: String,
  deleted_msg: String,
) -> Result(BotContext, BotError) {
  let value = string.lowercase(new_value)
  let current_state =
    setting_selector(ctx.session.chat_settings) |> list.map(string.lowercase)

  let #(new_state, msg) = case list.contains(current_state, value) {
    True -> #(
      list.filter(current_state, fn(x) { string.lowercase(x) != value }),
      deleted_msg,
    )

    False -> #([value, ..current_state], inserted_msg)
  }

  use _ <- result.try(cs_storage.save_chat_property(
    ctx.session.db,
    ctx.update.chat_id,
    setting_path,
    json.array(new_state, json.string),
  ))

  use _ <- result.try(reply(ctx, msg))

  Ok(ctx)
}
