import gleam/int
import gleam/list
import gleam/option
import gleam/string

pub fn try_parse_int(text: String, pos: Int) {
  raw_args(text)
  |> at(pos)
  |> option.map(fn(x) { int.parse(x) |> option.from_result })
  |> option.flatten
}

pub fn try_parse_str(text: String, pos: Int) {
  raw_args(text)
  |> at(pos)
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
