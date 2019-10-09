#include "share/atspre_staload.hats"
#include "share/atspre_staload_libats_ML.hats"

#include "patsec/lib.hats"

#define ATS_DYNLOADFLAG 0

staload "parser.sats"

implement version_to_string(version) =
    itoa(version.major) + "." + itoa(version.minor) + "." + itoa(version.patch)

fun print_version(version: Version) =
    println!(version.to_string())

fun print_dependency(dependency: Dependency) = (
    println!("Dependency: ", dependency.name);
    println!("    Git: ", dependency.git);
    print!("    ");
    print_version(dependency.version)
)

fun print_toml(project: Project) = (
    println!("Name: ", project.name);
    print!("Version: ");
    print_version(project.version);
    list0_foreach(project.dependencies, lam(dependency) => print_dependency(dependency))
)

fun {a: t@ype} key_value(key: string, value: Parser(a)): Parser(a) =
    string(key) *> spaces() *> char '=' *> spaces() *>
    between(char '"', char '"', value)

fun version(): Parser(Version) =
    natural() >>= (lam(major) =>
    char '.' *>
    natural() >>= (lam(minor) =>
    char '.' *>
    natural() >>= (lam(patch) =>
    return('{
        major = major,
        minor = minor,
        patch = patch
    })
    )))

fun ident(): Parser(string) =
    (alpha() <|> char '_') >>= (lam(first_char) =>
    many(alpha_num() <|> char '_') >>= (lam(rest) =>
    return(char2string(first_char) + string_make_list0(rest))
    ))

fun string_value(): Parser(string) =
    many1(none_of("\"")) >>= (lam(string) =>
    return(string_make_list0(string))
    )

fun dependency(): Parser(Dependency) =
    many(newline()) *>
    string("[dependencies.") *>
    ident() >>= (lam(name) =>
    char ']' *>
    newline() *>
    key_value("git", string_value()) >>= (lam(url) =>
    newline() *>
    key_value("version", version()) >>= (lam(version) =>
    many(newline()) *>
    return('{
        name = name,
        git = url,
        version = version
        }
    ))))

fun project(): Parser(Project) =
    string("[project]") *>
    newline() *>
    key_value("name", ident()) >>= (lam(name) =>
    newline() *>
    key_value("version", version()) >>= (lam(version) =>
    newline() *>
    option("", key_value("cflags", string_value()) <* newline()) >>= (lam(cflags) =>
    return('{
        cflags = cflags,
        name = name,
        version = version,
        dependencies = nil0()
    })
    )))

fun project_description(): Parser(Project) =
    project() >>= (lam(project) =>
    many(newline()) *>
    many_till(dependency(), eof()) >>= (lam(dependencies) =>
    return('{
        cflags = project.cflags,
        name = project.name,
        version = project.version,
        dependencies = dependencies
    })
    ))

implement parse_project_description(source) =
    parse(project_description(), source)

implement parse_project_file(filename) =
    let val file = fileref_open_exn(filename, file_mode_r)
        val content = list0_map(fileref_get_lines_stringlst(file), lam(line) => string_append(line, "\n"))
        val source = stringlst_concat(content)
    in
        parse_project_description(source)
    end
