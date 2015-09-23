import TimeZones: TimeZone

const TZFILE_DIR = normpath(joinpath(dirname(@__FILE__), "..", "tzfile"))

testnames = [
    "Africa/Abidjan",
    "America/Argentina/Buenos_Aires",
    "Africa/Dar_es_Salaam",
    "America/Port-au-Prince",
    "WET"
]

if OS_NAME == :Darwin
    for testname in testnames
        # Determine timezone via systemsetup.
        mock_readall(cmd) = "Time Zone:  $testname\n"
        patches = [
            Patch(Base, :readall, mock_readall)
        ]
        patch(patches) do
            @test TimeZones.localzone().name == TimeZone(testname).name
        end

        # Determine timezone from /etc/localtime.
        mock_readall(cmd) = ""
        mock_readlink(filename) = "/usr/share/zoneinfo/$testname"
        patches = [
            Patch(Base, :readall, mock_readall)
            Patch(Base, :readlink, mock_readlink)
        ]
        patch(patches) do
            @test TimeZones.localzone().name == TimeZone(testname).name
        end
    end

elseif OS_NAME == :Windows
    # Test Windows
    mock_readall(args) = "Central Standard Time\r\n"
    patches = [
        Patch(Base, :readall, mock_readall)
    ]
    patch(patches) do
        @test string(TimeZones.localzone()) == "America/Chicago"
    end
else # Linux
    withenv("TZ" => nothing) do
        for testname in testnames
            # Determine timezone from /etc/timezone (Unix).
#            mock_isfile(filename) = filename == "/etc/timezone" || contains(filename, PKG_DIR)
#            mock_open(filename) = IOBuffer("$testname #Works with comments\n")
#            mock_open(filename, arg) = Base.open(filename, arg)
#            patches = [
#                Patch(Base, :isfile, mock_isfile)
#                Patch(Base, :open, mock_open)
#            ]
#            patch(patches) do
#                @test TimeZones.localzone().name == TimeZone(testname).name
#            end
#
#            # Determine timezone from /etc/conf.d/clock (Unix).
#            mock_isfile(filename) = filename == "/etc/conf.d/clock" || contains(filename, PKG_DIR)
#            mock_open(filename) = IOBuffer("\n\nTIMEZONE=\"$testname\"")
#            mock_open(filename, arg) = Base.open(filename, arg)
#            patches = [
#                Patch(Base, :isfile, mock_isfile)
#                Patch(Base, :open, mock_open)
#            ]
#            patch(patches) do
#                @test TimeZones.localzone().name == TimeZone(testname).name
#            end

            # Determine timezone from /etc/localtime (Unix).
            mock_isfile(filename) = filename == "/etc/localtime" || contains(filename, PKG_DIR)
            mock_islink(filename) = filename == "/etc/localtime"
            mock_readlink(filename) = "/usr/share/zoneinfo/$testname"
            patches = [
                Patch(Base, :isfile, mock_isfile)
                Patch(Base, :islink, mock_islink)
                Patch(Base, :readlink, mock_readlink)
            ]
            patch(patches) do
                @test TimeZones.localzone().name == TimeZone(testname).name
            end

            # Unable to determine timezone (Unix).
            mock_isfile(filename) = false || contains(filename, PKG_DIR)
            mock_islink(filename) = false
            patches = [
                Patch(Base, :isfile, mock_isfile)
                Patch(Base, :islink, mock_islink)
            ]
            patch(patches) do
                @test_throws ErrorException TimeZones.localzone()
            end

            # Test TZ environmental variable (Unix).
            withenv("TZ" => ":$testname") do
                @test TimeZones.localzone().name == TimeZone(testname).name
            end
        end

        withenv("TZ" => "") do
            @test_throws ErrorException TimeZones.localzone()
        end
    end

    # Test TZ environmental variables (Unix).
    withenv("TZ" => ":bad") do
        @test_throws ErrorException TimeZones.localzone()
    end
    withenv("TZ" => "") do
        @test_throws ErrorException TimeZones.localzone()
    end

    # Reading a tzinfo file in "TZ"
    withenv("TZ" => joinpath(TZFILE_DIR, "Warsaw")) do
        timezone = TimeZones.localzone()
        @test string(timezone) == "local"
        @test length(timezone.transitions) == 167
        transition = timezone.transitions[166]
        @test transition.utc_datetime == Dates.DateTime(2037, 03, 29, 1)
        @test string(transition.zone.name) == "CEST"
        @test transition.zone.offset.utc == Dates.Second(3600)
        @test transition.zone.offset.dst == Dates.Second(3600)
    end

    # No explicit setting existed. Use localtime (Unix)
    #withenv("TZ" => nothing) do
    #    mock_isfile(filename) = filename == "usr/local/etc/localtime" ||
    #        contains(filename, PKG_DIR)
    #    mock_open(filename) = Base.open(test_tzinfo)
    #    patches = [
    #        Patch(Base, :isfile, mock_isfile)
    #        Patch(Base, :open, mock_open)
    #    ]
    #
    #    patch(patches) do
    #        timezone = TimeZones.localzone()
    #        @test string(timezone) == "local"
    #        @test length(timezone.transitions) == 167
    #        transition = timezone.transitions[166]
    #        @test transition.utc_datetime == Dates.DateTime(2037, 03, 29, 1)
    #        @test string(transition.zone.name) == "CEST"
    #        @test transition.zone.offset.dst == Dates.Second(3600)
    #        @test transition.zone.offset.utc == Dates.Second(3600)
    #    end
    #end


    # "Pacific/Apia" was the timezone I was thinking could be an issue for the
    # DST calculation. The entire day of 2011/12/30 was skipped when they changed from a
    # -11:00 GMT offset to 13:00 GMT offset
    withenv("TZ" => joinpath(TZFILE_DIR, "Apia")) do
        timezone = TimeZones.localzone()
        @test string(timezone) == "local"
        @test length(timezone.transitions) == 58

        transition = timezone.transitions[4]
        @test transition.utc_datetime == Dates.DateTime(2011, 04, 02, 14)
        @test string(transition.zone.name) == "SST"
        @test transition.zone.offset.utc == Dates.Second(-39600)
        @test transition.zone.offset.dst == Dates.Second(0)

        transition = timezone.transitions[5]
        @test transition.utc_datetime == Dates.DateTime(2011, 09, 24, 14)
        @test string(transition.zone.name) == "SDT"
        @test transition.zone.offset.utc == Dates.Second(-39600)
        @test transition.zone.offset.dst == Dates.Second(3600)

        transition = timezone.transitions[6]
        @test transition.utc_datetime == Dates.DateTime(2011, 12, 30, 10)
        @test string(transition.zone.name) == "WSDT"
        @test transition.zone.offset.utc == Dates.Second(46800)
        @test transition.zone.offset.dst == Dates.Second(3600)
    end

    # Because tzinfo files only store a single offset if both utc and dst change at the same
    # time then the resulting utc and dst might not be quite right. Most notably during
    # midsomer back in 1940's there were 2 different dst one after another, we get a
    # different utc and dst than Olson.
    withenv("TZ" => joinpath(TZFILE_DIR, "Paris")) do
        timezone = TimeZones.localzone()
        @test string(timezone) == "local"
        @test length(timezone.transitions) == 183

        transition = timezone.transitions[55]
        @test transition.utc_datetime == Dates.DateTime(1944, 04, 03, 1)
        @test string(transition.zone.name) == "CEST"
        @test transition.zone.offset.utc == Dates.Second(3600)
        @test transition.zone.offset.dst == Dates.Second(3600)

        transition = timezone.transitions[56]
        @test transition.utc_datetime == Dates.DateTime(1944, 08, 24, 22)
        @test string(transition.zone.name) == "WEMT"
        # Olson shows it as 0,7200
        @test transition.zone.offset.utc == Dates.Second(3600)
        @test transition.zone.offset.dst == Dates.Second(3600)

        transition = timezone.transitions[57]
        @test transition.utc_datetime == Dates.DateTime(1944, 10, 07, 23)
        @test string(transition.zone.name) == "WEST"
        @test transition.zone.offset.utc == Dates.Second(0)
        @test transition.zone.offset.dst == Dates.Second(3600)

        transition = timezone.transitions[58]
        @test transition.utc_datetime == Dates.DateTime(1945, 04, 02, 1)
        @test string(transition.zone.name) == "WEMT"
        # Olson shows it as 0,7200
        @test transition.zone.offset.utc == Dates.Second(3600)
        @test transition.zone.offset.dst == Dates.Second(3600)
    end

    withenv("TZ" => joinpath(TZFILE_DIR, "Madrid")) do
        timezone = TimeZones.localzone()
        @test string(timezone) == "local"
        @test length(timezone.transitions) == 163

        transition = timezone.transitions[32]
        @test transition.utc_datetime == Dates.DateTime(1946, 04, 13, 22)
        @test string(transition.zone.name) == "WEMT"
        # Olson shows it as 0,7200
        @test transition.zone.offset.utc == Dates.Second(3600)
        @test transition.zone.offset.dst == Dates.Second(3600)

        transition = timezone.transitions[33]
        @test transition.utc_datetime == Dates.DateTime(1946, 09, 29, 22)
        # Olson shows it as CEMT
        @test string(transition.zone.name) == "CET"
        # Olson shows it as 3600,7200
        @test transition.zone.offset.utc == Dates.Second(3600)
        @test transition.zone.offset.dst == Dates.Second(0)

        transition = timezone.transitions[34]
        @test transition.utc_datetime == Dates.DateTime(1949, 04, 30, 22)
        @test string(transition.zone.name) == "CEST"
        @test transition.zone.offset.utc == Dates.Second(3600)
        @test transition.zone.offset.dst == Dates.Second(3600)

        transition = timezone.transitions[35]
        @test transition.utc_datetime == Dates.DateTime(1949, 09, 29, 23)
        @test string(transition.zone.name) == "CET"
        @test transition.zone.offset.utc == Dates.Second(3600)
        @test transition.zone.offset.dst == Dates.Second(0)
    end
end
