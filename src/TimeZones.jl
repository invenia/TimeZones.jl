module TimeZones

using Base.Dates
import Base.Dates: AbstractTime, days, hour, minute, second, millisecond

export TimeZone, FixedTimeZone, VariableTimeZone, ZonedDateTime,
    TimeError, AmbiguousTimeError, NonExistentTimeError, DateTime,
    # accessors.jl
    hour, minute, second, millisecond,
    # adjusters.jl
    firstdayofweek, lastdayofweek,
    firstdayofmonth, lastdayofmonth,
    firstdayofyear, lastdayofyear,
    firstdayofquarter, lastdayofquarter,
    # Re-export from Base.Dates
    yearmonthday, yearmonth, monthday, year, month, week, day, dayofmonth,
    # local timezone
    localzone

const PKG_DIR = normpath(joinpath(dirname(@__FILE__), "..", "deps"))
const TZDATA_DIR = joinpath(PKG_DIR, "tzdata")
const COMPILED_DIR = joinpath(PKG_DIR, "compiled")
const WINDOWS_DIR = joinpath(PKG_DIR, "windows")

include("timezones/time.jl")
include("timezones/types.jl")
include("timezones/accessors.jl")
include("timezones/arithmetic.jl")
include("timezones/io.jl")
include("timezones/adjusters.jl")
include("timezones/Olsen.jl")
include("timezones/conversions.jl")
include("timezones/local.jl")

function TimeZone(name::String)
    tz_path = joinpath(COMPILED_DIR, split(name, "/")...)

    isfile(tz_path) || error("Unknown timezone $name")

    open(tz_path, "r") do fp
        return deserialize(fp)
    end
end

function timezone_names()
    names = String[]
    check = Tuple{String,String}[(COMPILED_DIR, "")]

    for (dir, partial) in check
        for filename in readdir(dir)
            startswith(filename, ".") && continue

            path = joinpath(dir, filename)
            name = partial == "" ? filename : join([partial, filename], "/")

            if isdir(path)
                push!(check, (path, name))
            else
                push!(names, name)
            end
        end
    end

    return sort(names)
end

end # module