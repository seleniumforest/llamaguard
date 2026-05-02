import gleam/int
import gleam/io
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp

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

fn with_datetime(str: String) -> String {
  let now =
    timestamp.system_time()
    |> timestamp.to_calendar(calendar.utc_offset)

  format("[{0} {1} {2} {3}:{4}:{5}]: {6}", [
    now.0.day |> int.to_string,
    now.0.month |> calendar.month_to_string,
    now.0.year |> int.to_string,
    now.1.hours |> int.to_string,
    now.1.minutes |> int.to_string,
    now.1.seconds |> int.to_string,
    str,
  ])
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
