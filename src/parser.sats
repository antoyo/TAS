#include "share/atspre_staload_libats_ML.hats"

#include "atstd/lib.hats"
#include "patsec/lib.hats"

typedef Version =
   '{ major = int
    , minor = int
    , patch = int
    }

fun version_to_string(version: Version): string

overload .to_string with version_to_string

typedef Dependency =
   '{ name = string
    , git = string
    , version = Version
    }

typedef Project =
   '{ cflags = string
    , name = string
    , version = Version
    , dependencies = list0(Dependency)
    }

fun parse_project_description(source: string): Result(Project, Error)

fun parse_project_file(filename: string): Result(Project, Error)
