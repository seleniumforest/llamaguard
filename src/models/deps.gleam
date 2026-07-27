import models/error
import telega/storage

pub type Deps {
  //todo move here all the deps from session
  Deps(cache: storage.KeyValueStorage(error.BotError), log: LogLvl)
}

pub type LogLvl {
  Debug
  Verbose
}
