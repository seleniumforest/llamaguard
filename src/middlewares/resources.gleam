import gleam/list
import gleam/string
import infra/alias
import models/bot_session
import simplifile
import telega/bot
import telega/update

pub fn inject_resources(resources: bot_session.Resources) {
  fn(next) {
    fn(ctx: alias.BotContext, update: update.Update) {
      let session = bot_session.BotSession(..ctx.session, resources:)
      let modified_ctx = bot.Context(..ctx, session:)
      next(modified_ctx, update)
    }
  }
}

pub fn load_static_resources() {
  let names = load_lines("./res/female_names.txt")
  let names_rus = load_lines("./res/female_names_rus.txt")

  bot_session.Resources(
    female_names: names
    |> list.append(names_rus)
    |> list.unique
    |> list.map(fn(x) { string.lowercase(x) }),
  )
}

fn load_lines(path: String) {
  let lines = simplifile.read(path)
  case lines {
    Error(e) -> {
      let msg =
        "Cannot load file: " <> path <> " Error: " <> e |> string.inspect
      panic as msg
    }
    Ok(content) -> {
      content
      |> string.split("\n")
      |> list.filter(fn(x) { string.length(x) > 0 })
    }
  }
}
