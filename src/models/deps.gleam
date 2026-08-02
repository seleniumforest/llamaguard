import gleam/erlang/process.{type Subject}
import models/error
import telega/storage

pub type Deps(storage_message) {
  //todo move here all the deps from session
  Deps(
    cache: storage.KeyValueStorage(error.BotError),
    log: LogLvl,
    db: Subject(storage_message),
    resources: Resources,
    services: Services,
  )
}

pub type Services {
  Services(cas_service: CasService)
}

pub type CasService {
  CasService(cas_check: fn(Int) -> Result(Int, error.BotError))
}

pub type Resources {
  Resources(female_names: List(String), unicode_script_extensions: List(String))
}

pub type LogLvl {
  Debug
  Verbose
}
