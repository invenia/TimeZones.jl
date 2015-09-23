# Determine the local systems timezone
# Based upon Python's tzlocal https://pypi.python.org/pypi/tzlocal
@osx_only function localzone()
    zone = readall([`systemsetup -gettimezone`]...)
    if contains(zone, "Time Zone: ")
        zone = strip(replace(zone, "Time Zone: ", ""))
    else
        zone = readlink(["/etc/localtime"]...)
        # link will be something like /usr/share/zoneinfo/America/Winnipeg
        zone = match(r"(?<=zoneinfo/).*$", zone).match
    end
    return TimeZone(zone)
end

@linux_only function localzone()
    validnames = timezone_names()

    # Try getting the time zone "TZ" environment variable
    # http://linux.die.net/man/3/tzset
    zone = Nullable{AbstractString}(get(ENV, "TZ", nothing))
    if !isnull(zone)
        zone_str = get(zone)
        if startswith(zone_str,':')
            zone_str = zone_str[2:end]
        end
        zone_str in validnames && return TimeZone(zone_str)

        # Read the tzfile to get the timezone
        try
            return build_tzinfo("local", zone_str)
        catch
            error("Failed to resolve local timezone from \"TZ\" environment variable.")
        end
    end

    # Look for distribution specific configuration files
    # that contain the timezone name.

    filename = "/etc/timezone"
    if isfile([filename]...)
        file = open([filename]...)
        try
            zone = readall(file)
            # Get rid of host definitions and comments:
            zone = strip(replace(zone, r"#.*", ""))
            zone = replace(zone, ' ', '_')
            zone in validnames && return TimeZone(zone)
        finally
            close(file)
        end
    end

    # CentOS has a ZONE setting in /etc/sysconfig/clock,
    # OpenSUSE has a TIMEZONE setting in /etc/sysconfig/clock and
    # Gentoo has a TIMEZONE setting in /etc/conf.d/clock

    zone_re = r"(?:TIME)?ZONE\s*=\s*\"(.*?)\""
    for filename in ("/etc/sysconfig/clock", "/etc/conf.d/clock")
        isfile([filename]...) || continue
        file = open([filename]...)
        try # Make sure we close the file
            for line in readlines(file)
                matched = match(zone_re, line)
                if matched != nothing
                    zone = matched.captures[1]
                    zone = replace(zone, ' ', '_')

                    zone in validnames && return TimeZone(zone)
                end
            end
        finally
            close(file)
        end
    end

    # systemd distributions use symlinks that include the zone name,
    # see manpage of localtime(5) and timedatectl(1)
    link = "/etc/localtime"
    if islink([link]...)
        zone = readlink([link]...)
        start = search(zone, '/')

        while start != 0
            zone = zone[(start+1):end]

            zone in validnames && return TimeZone(zone)

            start = search(zone, '/')
        end
    end

    # No explicit setting existed. Use localtime
    for filename in ("etc/localtime", "usr/local/etc/localtime")
        isfile([filename]...) || continue
        return build_tzinfo("local", filename)
    end

    error("Failed to find local timezone")
end

@windows_only function localzone()
    isfile(TRANSLATION_FILE) ||
        error("Windows zones not found. Try running Pkg.build(\"TimeZones\")")

    win_tz_dict = nothing
    open(TRANSLATION_FILE, "r") do fp
        win_tz_dict = deserialize(fp)
    end

    winzone = strip(readall(`powershell -Command "[TimeZoneInfo]::Local.Id"`))
    if haskey(win_tz_dict, winzone)
        timezone = win_tz_dict[winzone]
    else
        error("Failed to determine your Windows timezone. ",
            "Uses powershell, should work on windows 7 and above")
    end

    return TimeZone(timezone)
end

type TTInfo
    tt_gmtoff::Int32
    tt_isdst::Int8
    tt_abbrind::UInt8
end

function build_tzinfo(zone::AbstractString, filename::AbstractString)
    file = open([filename]...)
    try
        # Reference: http://man7.org/linux/man-pages/man5/tzfile.5.html
        magic = readbytes(file, 4)
        @assert magic == b"TZif" "Magic file identifier \"TZif\" not found."
        version = readbytes(file, 1)
        # Fifteen bytes containing zeros reserved for future use.
        readbytes(file, 15)
        # The number of UTC/local indicators stored in the file.
        tzh_ttisgmtcnt = bswap(read(file, Int32))
        # The number of standard/wall indicators stored in the file.
        tzh_ttisstdcnt = bswap(read(file, Int32))
        # The number of leap seconds for which data is stored in the file.
        tzh_leapcnt = bswap(read(file, Int32))
        # The number of "transition times" for which data is stored in the file.
        tzh_timecnt = bswap(read(file, Int32))
        # The number of "local time types" for which data is stored in the file (must not be zero).
        tzh_typecnt = bswap(read(file, Int32))
        # The number of characters of "timezone abbreviation strings" stored in the file.
        tzh_charcnt = bswap(read(file, Int32))

        transitions = Array{Int32}(tzh_timecnt)
        for index in 1:tzh_timecnt
            transitions[index] = bswap(read(file, Int32))
        end
        lindexes = Array{UInt8}(tzh_timecnt)
        for index in 1:tzh_timecnt
            lindexes[index] = bswap(read(file, UInt8)) + 1 # Julia uses 1 indexing
        end
        ttinfo = Array{TTInfo}(tzh_typecnt)
        for index in 1:tzh_typecnt
            ttinfo[index] = TTInfo(
                bswap(read(file, Int32)),
                bswap(read(file, Int8)),
                bswap(read(file, UInt8)) + 1 # Julia uses 1 indexing
            )
        end
        tznames_raw = Array{UInt8}(tzh_charcnt)
        namestart = 1
        tznames = Dict{UInt8, AbstractString}()
        for index in 1:tzh_charcnt
            tznames_raw[index] = bswap(read(file, UInt8))
            if tznames_raw[index] == '\0'
                tznames[namestart] = ascii(tznames_raw[namestart:index-1])
                namestart = index+1
            end
        end
        # Now build the timezone object
        if length(transitions) == 0
            return FixedTimeZone(Symbol(tznames[ttinfo[1].tt_abbrind]), Offset(ttinfo[1].tt_gmtoff))
        else
            # Calculate transition info
            transition_info = Transition[]
            prev_utc = 0
            prev_dst = 0
            dst = 0
            utc = 0
            for i in 1:length(transitions)
                inf = ttinfo[lindexes[i]]
                utcoffset = inf.tt_gmtoff
                if inf.tt_isdst == 0
                    utc = inf.tt_gmtoff
                    dst = 0
                else
                    if prev_dst == 0
                        utc = prev_utc
                        dst = inf.tt_gmtoff - prev_utc
                    else
                        utc = inf.tt_gmtoff - prev_dst
                        dst = prev_dst
                    end
                end
                if haskey(tznames, inf.tt_abbrind)
                    tzname = tznames[inf.tt_abbrind]
                else
                    # Sometimes it likes to be fancy and have multiple names in one for
                    # example "WSST" at tt_abbrind 5 turns into "SST" at tt_abbrind 6
                    name_offset = 1
                    while !haskey(tznames, (inf.tt_abbrind-name_offset))
                        name_offset+=1
                        if name_offset >= inf.tt_abbrind
                            error("Failed to find a tzname referenced in a transition.")
                        end
                    end
                    tzname = tznames[inf.tt_abbrind-name_offset][name_offset+1:end]
                    tznames[inf.tt_abbrind] = tzname
                end
                push!(
                    transition_info,
                    Transition(
                        unix2datetime(transitions[i]),
                        FixedTimeZone(Symbol(tzname),
                        Offset(utc, dst))
                    )
                )
                prev_utc = utc
                prev_dst = dst
            end
            return VariableTimeZone(Symbol(zone), transition_info)
        end
    catch
        rethrow()
    finally
        close(file)
    end
end
