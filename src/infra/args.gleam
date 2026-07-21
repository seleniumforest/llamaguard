import gleam/bool
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import infra/log
import models/error

pub fn try_parse_int(cmd_text: String, pos: Int) {
  raw_args(cmd_text)
  |> at(pos)
  |> option.map(fn(x) { int.parse(x) |> option.from_result })
  |> option.flatten
}

pub fn try_parse_str(cmd_text: String, pos: Int) {
  raw_args(cmd_text)
  |> at(pos)
}

pub fn use_first_arg(
  cmd_text: String,
  conversion: fn(String) -> argtype,
  fallback: fn() -> rettype,
  continuation: fn(argtype) -> rettype,
) {
  let arg =
    raw_args(cmd_text)
    |> at(1)

  case arg {
    option.Some(arg) -> arg |> conversion |> continuation
    option.None -> fallback()
  }
}

pub fn parse_str(text: String, pos: Int, continuation) {
  raw_args(text)
  |> at(pos)
  |> option.to_result(
    error.GenericError(
      log.format("ERROR: Cannot parse argument at pos {0}. text: {1}", [
        int.to_string(pos),
        text,
      ]),
    ),
  )
  |> result.try(continuation)
}

pub fn args_count(text: String) {
  text
  |> string.split(" ")
  |> list.rest()
  |> result.unwrap([])
  |> list.filter(fn(x) { x |> string.is_empty |> bool.negate })
  |> list.length
}

fn raw_args(text: String) {
  text
  |> string.split(" ")
  |> list.filter(fn(x) { x != "" })
}

fn at(list: List(s), pos: Int) {
  case list {
    [] -> option.None
    [first, ..] if pos == 0 -> option.Some(first)
    [_, ..rest] -> at(rest, pos - 1)
  }
}
