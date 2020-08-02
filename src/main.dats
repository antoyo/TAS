(*
 * FIXME: run should return the exit code of the executed process.
 *
 * FIXME: recompile (what? everything?) if project.toml was changed.
 *
 * TODO: error when a dependency file is not found (instead of having an undefined reference).
 * TODO: Maybe use `git ls-remote --refs --tags https://github.com/git/git.git "v2.1*"` to only fetch the tags that are needed for the specified version?
 * TODO: do not attempt to compile the executable if there was an error (stop at first error).
 *
 * TODO: instead of creating symlinks, rename src to package_name.
 *
 * TODO: the flag -DATS_MEMALLOC_GCBDW should probably be used when needing the GC.
 *)

#include "share/atspre_staload.hats"
#include "share/atspre_staload_libats_ML.hats"

staload "libats/libc/SATS/stdio.sats"
staload _ = "libats/libc/DATS/stdlib.dats"
staload STDLIB = "libats/libc/SATS/stdlib.sats"
staload _ = "libats/libc/DATS/sys/stat.dats"
staload STAT = "libats/libc/SATS/sys/stat.sats"
staload TYPES = "libats/libc/SATS/sys/types.sats"
staload UNISTD = "libats/libc/SATS/unistd.sats"
staload UNSAFE = "prelude/SATS/unsafe.sats"

#include "atstd/lib.hats"
#include "clast/lib.hats"
#include "patsec/lib.hats"

#define ATS_PACKNAME "tas"

staload "parser.sats"

infixr .|.
macdef .|. (a, b) = $TYPES.lor(,(a), ,(b))

%{^
#include <unistd.h>
%}

typedef Node =
   '{ children = list0(size_t)
    , compiled_at = uint
    , filename = string
    , modified = uint
    , object_file = string
    , to_compile = ref(bool)
    }

typedef BuildResult =
   '{ cflags = string
    , executable_name = string
    , dependency_includes = string
    , project_name = string
    , dependency_graph = array0(Node)
    }

datatype BuildType =
    | CurrentProject
    | ProjectDependency

fn build_type_eq(build_type1: BuildType, build_type2: BuildType): bool =
    case+ (build_type1, build_type2) of
    | (CurrentProject(), CurrentProject()) => true
    | (ProjectDependency(), ProjectDependency()) => true
    | (CurrentProject(), ProjectDependency()) => false
    | (ProjectDependency(), CurrentProject()) => false

overload = with build_type_eq

extern fun chdir(path: NSH(string)): int = "mac#"

fun list_files(directory: string): list0(string) =
    list0_mapopt<string><string>(dirname_get_fnamelst(directory), lam(filename) =>
        if filename = "." || filename = ".." then
            None_vt()
        else
            Some_vt(directory + "/" + filename)
    )

fun remove_dir(directory: string) =
    let val files = list_files(directory)
    in
        list0_foreach(files, lam(file) =>
            if test_file_isdir(file) = 1 then (
                remove_dir(file);
                ignoret($UNISTD.rmdir(file))
            )
            else
                ignoret($UNISTD.unlink(file))
        );
        ignoret($UNISTD.rmdir(directory))
    end

fun create_directory(directory: string) =
    ignoret($STAT.mkdirp(directory,
        $STAT.S_IRWXU .|. $STAT.S_IRGRP .|. $STAT.S_IXGRP .|. $STAT.S_IROTH .|. $STAT.S_IXOTH))

fun string_rfind(string: string, char_to_find: char): size_t =
    let val found_index = ref<int>(0)
    in (
        string_iforeach(string, lam(index, char) =>
            if char = char_to_find then
                !found_index := index
        );
        g0i2u(!found_index)
    )
    end

fun string_make_suffix(string: string, start: size_t): string =
    let val size = string0_length(string)
    in
        string_make_substring(string, start, size - start)
    end

val verbose = ref<bool>(false)

fun execute_status(command: string): (list0(string), int) =
    let val () =
            if !verbose then
                println!("Executing `", command, "`")
        val file = popen_exn(command, $UNSAFE.cast{pmode(r)}("r"))
        val result = fileref_get_lines_stringlst(file)
    in (
        (result, pclose0_exn(file))
    )
    end

fun execute(command: string): list0(string) =
    let val (stdout, _status) = execute_status(command)
    in
        stdout
    end

fun execute_string(command: string): (string, int) =
    let val (stdout, status) = execute_status(command + " 2>&1 > /dev/null")
    in
        (stringlst_concat(stdout), status)
    end

(*
 * TODO: Use getpwuid(getuid()).pw_dir when the environement variable does not contain a value.
 *)
fun get_home_dir(): option0(string) =
    getenv_opt("HOME")

fun get_cache_dir(home_dir: string): string =
    home_dir + "/.cache/tas"

fun init_cache(): string =
    case+ get_home_dir() of
    | Some0(home_dir) =>
        let val directory = get_cache_dir(home_dir)
        in (
            create_directory(directory);
            directory
        )
        end
    | None0() => (
        prerrln!("tas: cannot initialize cache as no home directory was found");
        ignoret(exit(1));
        ""
    )

fun string_find(str: string, string_to_search: string): option0(size_t) =
    let val substring_len = string_length(string_to_search)
        val len = string_length(str)
        fun find(index: size_t) =
            if index >= len then
                None0()
            else if string_make_substring(str, index, substring_len) = string_to_search then
                Some0(index)
            else
                find(index + 1)
    in
        find(i2sz(0))
    end

fun string_split2(str: string, separator: string): @(string, string) =
    case+ string_find(str, separator) of
    | None0() => @(str, "")
    | Some0(index) =>
        let val start = index + string_length(separator)
            val end_index = string_length(str)
        in
            @(string_make_substring(str, i2sz(0), index), string_make_substring(str, start, end_index))
        end

fun string_split(str: string, separator: string): list0(string) =
    let val @(str, rest) = string_split2(str, separator)
    in
        if string_is_empty(rest) then
            list0_sing(str)
        else
            cons0(str, string_split(rest, separator))
    end

fun symlink_exists(filename: string): bool =
    let var stat: $STAT.stat?
        val error = $STAT.lstat(filename, stat)
    in
        if error >= 0 then
            let prval () = opt_unsome{$STAT.stat}(stat)
            in
                true
            end
        else
            let prval () = opt_unnone{$STAT.stat}(stat)
            in
                false
            end
    end

fun file_modified(filename: string): uint =
    let var stat: $STAT.stat?
        val error = $STAT.stat(filename, stat)
    in
        if error >= 0 then
            let prval () = opt_unsome{$STAT.stat}(stat)
            in
                $UN.cast{uint}(stat.st_mtime)
            end
        else
            let prval () = opt_unnone{$STAT.stat}(stat)
            in
                0u
            end
    end

fun dependency_version_directory(cache_dir: string, dependency: Dependency): string =
    cache_dir + "/" + dependency.name + "/" + dependency.version.to_string()

fun dependency_directory(cache_dir: string, dependency: Dependency): string =
    dependency_version_directory(cache_dir, dependency) + "/" + dependency.name

fun create_dependency_graph(cache_dir: string, dependencies: list0(Dependency), build_type: BuildType,
        release_mode: bool): (string, array0(Node)) =
    let val filenames =
            if build_type = ProjectDependency then
                list_files("src")
            else
                list0_append(list0_append(list_files("src"), list_files("examples")), list_files("tests"))
        val dep_filenames = list0_concat(list0_map(dependencies, lam(dependency) =>
            list_files(dependency_directory(cache_dir, dependency))
        ))
        val dependency_includes = stringlst_concat(list0_map(dependencies, lam(dependency) =>
            "-IATS \"" + dependency_version_directory(cache_dir, dependency) + "\" "
        ))
        val dependency_includes = "-IATS src " + dependency_includes
        val filenames = list0_append(filenames, dep_filenames)
        val dynamic_filenames = list0_filter(filenames, lam(filename) =>
            string_is_suffix(filename, ".dats") || string_is_suffix(filename, ".hats") ||
            string_is_suffix(filename, ".ats")
        )
        val static_filenames = list0_filter(filenames, lam(filename) =>
            string_is_suffix(filename, ".sats")
        )
        val filenames = dynamic_filenames + static_filenames
        val dynamic_files = stringlst_concat(list0_map(dynamic_filenames, lam(file) => file + " "))
        val static_files = stringlst_concat(list0_map(static_filenames, lam(file) => file + " "))
        val dependencies = execute("patsopt " + dependency_includes + " --depgen --dynamic " + dynamic_files +
            " --static " + static_files)
        val dependencies: list0(string) = list0_filter(dependencies, lam(line) => string_isnot_empty(line))
        val dependencies = list0_map<string>< @(string, list0(string))>(dependencies,
            lam(line) =>
                let val @(name, deps) = string_split2(line, " : ")
                    val deps = string_split(deps, " ")
                in
                    if geq_val_val<list0(string)>(deps, list0_sing("")) then
                        @(name, nil0())
                    else
                        @(name, deps)
                end
            )
        val nodes = array0_make_elt(list0_length(filenames),
           '{ children = nil0()
            , compiled_at = 0u
            , filename = ""
            , modified = 0u
            , object_file = ""
            , to_compile = ref(false)
            }
        )
        val _ = list0_imap2< @(string, list0(string)), string>< @()>(dependencies, filenames, lam(index, @(object_file, dependencies), filename) =>
            let val build_dir =
                    if release_mode then
                        "build/release/"
                    else
                        "build/debug/"
                fun adjust_path(object_file: string): string =
                    if string_is_prefix("/", object_file) then
                        let val index = string_rfind(object_file, '/')
                            val string_prefix = string_make_prefix(object_file, index + 1)
                            val suffix = string_make_substring(object_file, index + 1, string0_length(object_file) - string0_length(string_prefix))
                        in
                            string_prefix + build_dir + "src/" + suffix
                        end
                    else
                        build_dir + object_file
                val object_file = adjust_path(object_file)
            in (
                nodes[index] := '{
                    children = list0_mapopt<string><size_t>(dependencies, lam(dependency) =>
                        let val index = list0_find_index(filenames, lam(filename) => filename = dependency)
                        in
                            if index = ~1 then
                                None_vt()
                            else
                                Some_vt(g0int2uint(index))
                        end
                    ),
                    compiled_at = file_modified(object_file),
                    filename = filename,
                    modified = file_modified(filename),
                    object_file = object_file,
                    to_compile = ref(false)
                };
                @()
            )
            end
        )
    in
        (dependency_includes, nodes)
    end

fun list0_max(xs: list0(uint)): uint =
    list0_foldleft(xs, g0int2uint(0), lam(acc, modified) => max(acc, modified))

fun walk_graph(graph: array0(Node)) =
    let val nodes_modified = array0_map(graph, lam(node) => node.modified)
        val nodes_max_modified: array0(uint) = array0_map(graph, lam(node) =>
            max(
                node.modified,
                list0_max(list0_map(node.children, lam(index) => nodes_modified[index]))
            )
        )
        fun needs_compiling(index: size_t): bool =
            let val node = graph[index]
                val outdated = string_is_suffix(node.filename, ".dats") && node.compiled_at < node.modified
            in
                outdated || node.compiled_at < nodes_max_modified[index]
            end
    in
        array0_iforeach(graph, lam(index, node) =>
            !(node.to_compile) := needs_compiling(index))
    end

(* TODO: Create a record holding the compilation options. *)
fun compile_library(dependency_includes: string, graph: array0(Node), cache_dir: string, release_mode: bool,
    cflags: string, compile_filter: string -<cloref1> bool, exclude_filter: string -<cloref1> bool): list0(string) =
    array0_foldleft(graph, nil0(), lam(object_files, node) =>
        if string_is_suffix(node.filename, ".dats") then (
            if compile_filter(node.filename) && !(node.to_compile) then
                let val c_file = node.object_file + ".c"
                    val optimization_flag =
                        if release_mode then
                            "-O3"
                        else
                            "-g"
                    val debug_flag =
                        if release_mode then
                            ""
                        else
                            "--gline"
                in (
                    ignoret(execute("patsopt " + debug_flag + " -IATS src " + dependency_includes + " --output " + c_file + " --dynamic " + node.filename));
                    ignoret(execute("gcc " + cflags + " " + optimization_flag + " -c -std=c99 -D_XOPEN_SOURCE -I${PATSHOME} -I${PATSHOME}/ccomp/runtime -L${PATSHOME}/ccomp/atslib/lib -DATS_MEMALLOC_LIBC -o " + node.object_file + " " + c_file));
                    ignoret($UNISTD.unlink(c_file));
                )
                end
            ;
            if ~exclude_filter(node.filename) && (compile_filter(node.filename) || string_is_prefix("src/", node.filename) ||
                string_is_prefix(cache_dir, node.filename))
            then
                cons0(node.object_file + " ", object_files)
            else
                object_files
        )
        else
            object_files
    )

fun compile_executable(binary_name: string, dependency_includes: string, graph: array0(Node), cache_dir: string,
    main_file: string, release_mode: bool, cflags: string, compile_filter: string -<cloref1> bool,
    exclude_filter: string -<cloref1> bool) :string =
(
    let val build_dir =
            if release_mode then
                "build/release/"
            else
                "build/debug/"
        val () = create_directory(build_dir + "src")
        val executable_name = build_dir + binary_name
        val object_files = compile_library(dependency_includes, graph, cache_dir, release_mode, cflags, compile_filter,
            exclude_filter);
        val is_binary = array0_exists(graph, lam(node) => node.filename = main_file)
        val has_compiled =
            array0_foldleft(graph, false, lam(has_compiled, node) =>
                if string_is_suffix(node.filename, ".dats") then
                    if !(node.to_compile) then
                        has_compiled || true
                    else
                        has_compiled
                else
                    has_compiled
            )
        val optimization_flag =
            if release_mode then
                "-O3"
            else
                "-g"
    in (
        if (has_compiled || ~test_file_exists(executable_name)) && is_binary then
            ignoret(execute("gcc " + cflags + " " + optimization_flag + " -o " + executable_name + " " + stringlst_concat(object_files) + " -L${PATSHOME}/ccomp/atslib/lib -latslib"))
        ;
        executable_name
    )
    end
)

fun getcwd(): option0(string) =
    let val current_dir = $UNISTD.getcwd_gc()
    in
        if isneqz current_dir then
          Some0(strptr2string(current_dir))
        else
            let prval () = strptr_free_null(current_dir)
            in
                None0()
            end
    end

fun build(cache_dir: string, build_type: BuildType, release_mode: bool): Result(BuildResult, Error) =
    let val project = parse_project_file("project.toml")
    in
        case+ project of
        | Ok(project) => (
            compile_dependencies(cache_dir, project, release_mode);
            let val project_name = project.name
                (* TODO: handle errors *)
                val (dependency_includes, graph) = create_dependency_graph(cache_dir, project.dependencies, build_type,
                        release_mode);
            in (
                println!("Compiling ", project_name);
                create_directory("build/src");
                walk_graph(graph);
                Ok(
                   '{ cflags = project.cflags
                    , executable_name = compile_executable(project_name, dependency_includes, graph, cache_dir,
                        "src/main.dats", release_mode, project.cflags,
                        lam(file) => string_is_prefix("src/", file), lam(_) => false)
                    , dependency_includes = dependency_includes
                    , project_name = project_name
                    , dependency_graph = graph
                    }
                )
            )
            end
        )
        | Err(error) => Err(error)
    end

and compile_dependencies(cache_dir: string, project: Project, release_mode: bool) =
    let val current_dir = getcwd()
    in (
        list0_foreach(project.dependencies, lam(dependency) =>
            let val directory = dependency_directory(cache_dir, dependency)
            in (
                if ~test_file_exists(directory) then (
                    let val tags = execute("git ls-remote --refs --tags " + dependency.git)
                        val src_dir = directory + "/src"
                        val tags = list0_mapopt<string><string>(tags, lam(tag) =>
                            if string_is_empty(tag) then
                                None_vt()
                            else
                                let val (_, tag) = string_split2(tag, "\t")
                                    val start_index = string_rfind(tag, '/') + 1
                                    val tag = string_make_suffix(tag, start_index)
                                in
                                    Some_vt(tag)
                                end
                        )
                        val current_version_tag = "v" + dependency.version.to_string()
                        val version_found = list0_exists(tags, lam(tag) => tag = current_version_tag)
                    in
                        if ~version_found then (
                            (* TODO: better error handling. *)
                            prerrln!("tas: cannot find tag " + current_version_tag + " for dependency " + dependency.name);
                            ignoret(exit(2));
                        );
                        ignoret(execute("git clone -b '" + current_version_tag + "' --single-branch --depth 1 " + dependency.git + " " + directory));
                        let val files = dirname_get_fnamelst(src_dir)
                        in
                            list0_foreach(files, lam(file) =>
                                if file <> ".." && file <> "." then
                                    ignoret($UNISTD.symlink_exn(src_dir + "/" + file, directory + "/" + file))
                            )
                        end
                    end
                );
                ignoret(chdir(directory));
                println!("In directory ", directory);
                case+ build(cache_dir, ProjectDependency, release_mode) of
                | Ok(_) => ()
                | Err(error) => prerrln!("Error parsing project.toml: ", error)
            )
            end
        );
        case+ current_dir of
        | Some0(current_dir) => ignoret(chdir(current_dir))
        | None0() => prerrln!("Cannot chdir") (* TODO: *)
    )
    end

fun create_project_symlinks(project_name: string) =
    let val files = dirname_get_fnamelst("src")
        val directory = "build/src/" + project_name
    in (
        create_directory(directory);
        list0_foreach(files, lam(file) =>
            let val symlink_name = directory + "/" + file
            in
                if file <> ".." && file <> "." && ~symlink_exists(symlink_name) then
                    ignoret($UNISTD.symlink_exn("../../../src/" + file, symlink_name))
            end
        );
    )
    end

fun build_example(cache_dir: string, name: string, build_result: BuildResult, release_mode: bool): Result(string, Error) =
    let val dependency_includes = build_result.dependency_includes + " -IATS build/src"
        val build_dir =
            if release_mode then
                "build/release/examples"
            else
                "build/debug/examples"
    in (
        create_directory(build_dir);
        println!("Compiling example " + name);
        create_project_symlinks(build_result.project_name);
        Ok(compile_executable(name, dependency_includes, build_result.dependency_graph, cache_dir,
            "examples/" + name + ".dats", release_mode, build_result.cflags,
            lam(file) => string_is_prefix("examples/" + name, file),
            lam(file) => file = "src/main.dats"))
    )
    end

fun build_tests(cache_dir: string, build_result: BuildResult, release_mode: bool): Result(list0(string), Error) =
    let val tests = list_files("tests")
        val dependency_includes = build_result.dependency_includes + " -IATS build/src"
        val build_dir =
            if release_mode then
                "build/release/tests"
            else
                "build/debug/tests"
    in (
        create_directory(build_dir);
        create_project_symlinks(build_result.project_name);
        Ok(list0_map(tests, lam(test) => (
            let val start_index = string_rfind(test, '/') + 1
                val end_index = string_rfind(test, '.')
                val name = string_make_substring(test, start_index, end_index - start_index)
            in (
                println!("Compiling test " + name);
                compile_executable(name, dependency_includes, build_result.dependency_graph, cache_dir, test,
                    release_mode, build_result.cflags,
                    lam(file) => string_is_prefix(test, file), lam(file) => file = "src/main.dats")
            )
            end
        )))
    )
    end

typedef TestFailure =
   '{ name = string
    , stderr = string
    }

fun run_tests(tests: list0(string)) =
    let val test_count = list0_length(tests)
        val () = println!("\nrunning ", test_count, " tests")
        val fails =
            list0_foldleft<list0(TestFailure)>(tests, nil0(), lam(failures, test) =>
                let val start_index = string_rfind(test, '/') + 1
                    val name = string_make_substring(test, start_index, string0_length(test) - start_index)
                    val () = print!("test ", name, " ... ")
                    val (stderr, status) = execute_string(test)
                in
                    if status = 0 then (
                        println!("ok");
                        failures
                    )
                    else (
                        println!("FAILED");
                        cons0('{ name = name, stderr = stderr }, failures)
                    )
                end
            )
        val fail_count = list0_length(fails)
        val successes = test_count - fail_count
        val result =
            if fail_count = 0 then
                "ok"
            else
                "FAILED"
    in
        if fail_count > 0 then (
            println!("\nfailures:\n");
            list0_foreach(fails, lam(fail) => (
                println!("---- ", fail.name, " stderr ----");
                println!(fail.stderr, "\n")
            ));
            println!("failures:\n");
            list0_foreach(fails, lam(fail) => (
                println!("    ", fail.name);
            ));
        );
        println!("\ntest result: " + result, ". ", successes, " passed; ", fail_count, " failed");
    end

fun create_file(path: string, content: string) =
    let val file = fileref_open_exn(path, file_mode_w)
    in (
        fileref_put_string(file, content);
        fileref_close(file)
    )
    end

implement main0(argc, argv) =
    let val cache_dir = init_cache()
        val arg_parser = arg_parser(argc, argv)
        val build_subcommand = arg_parser.add_subcommand("build", "Compile the current project")
        val run_subcommand = arg_parser.add_subcommand("run", "Compile and run the current project")
        val test_subcommand = arg_parser.add_subcommand("test", "Run the tests")
        val new_subcommand = arg_parser.add_subcommand("new", "Create a new ats project")
        val clean_subcommand = arg_parser.add_subcommand("clean", "Remove the build directory and the object files")
    in (
        arg_parser.set_description("TAS build system");
        arg_parser.set_program_name("tas");
        ignoret(arg_parser.add_flag(
           '{ short_name = "h"
            , long_name = "help"
            , description = "Show help message"
            }
        ));
        ignoret(arg_parser.add_flag(
           '{ short_name = "v"
            , long_name = "version"
            , description = "Show version number"
            }
        ));
        ignoret(build_subcommand.add_flag(
           '{ short_name = "h"
            , long_name = "help"
            , description = "Show help message"
            }
        ));
        ignoret(build_subcommand.add_flag(
           '{ short_name = "v" (* TODO: remove short_name *)
            , long_name = "verbose"
            , description = "Show the commands used to compile"
            }
        ));
        ignoret(build_subcommand.add_arg(
           '{ short_name = "e" (* TODO: remove short_name *)
            , long_name = "example"
            , description = "Name of the example to run"
            , hint = "NAME"
            }
        ));
        ignoret(build_subcommand.add_flag(
           '{ short_name = "r" (* TODO: remove short_name *)
            , long_name = "release"
            , description = "Build artifacts in release mode, with optimizations"
            }
        ));
        ignoret(run_subcommand.add_flag(
           '{ short_name = "h"
            , long_name = "help"
            , description = "Show help message"
            }
        ));
        ignoret(run_subcommand.add_arg(
           '{ short_name = "e" (* TODO: remove short_name *)
            , long_name = "example"
            , description = "Name of the example to run"
            , hint = "NAME"
            }
        ));
        ignoret(run_subcommand.add_flag(
           '{ short_name = "r" (* TODO: remove short_name *)
            , long_name = "release"
            , description = "Build artifacts in release mode, with optimizations"
            }
        ));
        ignoret(test_subcommand.add_flag(
           '{ short_name = "h"
            , long_name = "help"
            , description = "Show help message"
            }
        ));
        ignoret(test_subcommand.add_flag(
           '{ short_name = "r" (* TODO: remove short_name *)
            , long_name = "release"
            , description = "Build artifacts in release mode, with optimizations"
            }
        ));
        ignoret(new_subcommand.add_flag(
           '{ short_name = "h"
            , long_name = "help"
            , description = "Show help message"
            }
        ));
        ignoret(new_subcommand.add_flag(
           '{ short_name = "l" (* TODO: remove short_name *)
            , long_name = "lib"
            , description = "Use a library template"
            }
        ));
        ignoret(clean_subcommand.add_flag(
           '{ short_name = "h"
            , long_name = "help"
            , description = "Show help message"
            }
        ));
        case+ arg_parser.parse() of
        | Ok(matches) => (
            let val release_mode = matches.get_flag("release")
            in
                if matches.get_flag("verbose") then
                    !verbose := true
                ;
                if matches.get_flag("help") then
                    case+ matches.subcommand of
                    | Some0(subcommand) => let val _ = arg_parser.print_usage(subcommand) in end
                    | None0() => arg_parser.print_usage()
                else if matches.is_subcommand("build") then
                    case+ build(cache_dir, CurrentProject, release_mode) of
                    | Ok(build_result) =>
                        (case+ matches.get_string("example") of
                        | Some0(example) =>
                            (case+ build_example(cache_dir, example, build_result, release_mode) of
                            | Ok(_) => ()
                            | Err(error) => prerrln!("Error compiling the example ", example, ": ", error)
                            )
                        | None0() => ()
                        )
                    | Err(error) => prerrln!("Error parsing project.toml: ", error)
                else if matches.is_subcommand("run") then (
                    case+ build(cache_dir, CurrentProject, release_mode) of
                    | Ok(build_result) =>
                        (case+ matches.get_string("example") of
                        | Some0(example) =>
                            (case+ build_example(cache_dir, example, build_result, release_mode) of
                            | Ok(executable_name) => (
                                (* TODO: give cli arguments after -- . *)
                                ignoret($STDLIB.system(executable_name))
                            )
                            | Err(error) => prerrln!("Error compiling the example ", example, ": ", error)
                            )
                        | None0() => ignoret($STDLIB.system(build_result.executable_name))
                        )
                    | Err(error) => prerrln!("Error parsing project.toml: ", error)
                )
                else if matches.is_subcommand("test") then (
                    case+ build(cache_dir, CurrentProject, release_mode) of
                    | Ok(build_result) =>
                        (case+ build_tests(cache_dir, build_result, release_mode) of
                        | Ok(tests) => run_tests(tests)
                        | Err(error) => prerrln!("Error compiling the tests: ", error)
                        )
                    | Err(error) => prerrln!("Error parsing project.toml: ", error)
                )
                else if matches.is_subcommand("new") then (
                    case+ matches.get_free_args() of
                    | list0_cons(project_name, _) => (
                        create_directory(project_name + "/src");
                        create_file(project_name + "/.gitignore", "build");
                        create_file(project_name + "/project.toml",
"[project]
name = \"" + project_name + "\"
version = \"0.0.1\"
");
                        let val end_content =
                                if matches.get_flag("lib") then
                                    ""
                                else
"
implement main0() = {
}
"
                            val content =
"#include \"share/atspre_staload.hats\"
#include \"share/atspre_staload_libats_ML.hats\"

#define ATS_PACKNAME \"" + project_name + "\"
" + end_content
                            val filename =
                                if matches.get_flag("lib") then
                                    "lib.dats"
                                else
                                    "main.dats"
                        in
                            create_file(project_name + "/src/" + filename, content)
                        end
                    )
                    | list0_nil() => prerrln!("error: The following required arguments were not provided:\n    <path>")
                )
                else if matches.is_subcommand("clean") then (
                    remove_dir("build");
                    let val project = parse_project_file("project.toml")
                    in
                        case+ project of
                        | Ok(project) =>
                            list0_foreach(project.dependencies, lam(dependency) =>
                                remove_dir(dependency_directory(cache_dir, dependency) + "/build")
                            )
                        | Err(error) => prerrln!("Error parsing project.toml: ", error)
                    end
                )
            end
        )
        | Err(error) => (
            prerrln!("Error: ", error);
            println!();
            arg_parser.print_usage() (* TODO: print the usage of the command if one was specified. *)
        )
    )
    end
