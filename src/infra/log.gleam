import gleam/int
import gleam/io
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import models/deps

pub fn format(format: String, data: List(String)) -> String {
  format_loop(format, data, 0)
}

pub fn printf(format: String, data: List(String)) {
  format_loop(format, data, 0) |> with_datetime |> io.println
}

pub fn print(format: String) {
  format_loop(format, [], 0) |> with_datetime |> io.println
}

pub fn printf_err(format: String, data: List(String)) {
  format_loop(format, data, 0) |> with_datetime |> io.println_error
}

pub fn print_err(format: String) {
  format_loop(format, [], 0) |> with_datetime |> io.println_error
}

pub fn debug(log_lvl: deps.LogLvl, msg: String) {
  case log_lvl {
    deps.Debug -> printf("DEBUG: {0}", [msg])
    deps.Verbose -> Nil
  }
}

fn with_datetime(str: String) -> String {
  let now =
    timestamp.system_time()
    |> timestamp.to_calendar(calendar.utc_offset)

  format("[{0} {1} {2} {3}:{4}:{5}]: {6}", [
    now.0.day |> pad_number,
    now.0.month |> calendar.month_to_string,
    now.0.year |> int.to_string,
    now.1.hours |> pad_number,
    now.1.minutes |> pad_number,
    now.1.seconds |> pad_number,
    str,
  ])
}

fn pad_number(num: Int) {
  case num {
    n if n < 10 && n >= 0 -> "0" <> int.to_string(num)
    _ -> int.to_string(num)
  }
}

fn format_loop(format: String, data: List(String), depth: Int) -> String {
  case data {
    [] -> format
    [first, ..rest] ->
      format_loop(
        string.replace(format, "{" <> int.to_string(depth) <> "}", first),
        rest,
        depth + 1,
      )
  }
}
