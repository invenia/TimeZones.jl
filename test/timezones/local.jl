import TimeZones: TimeZone

const TZFILE_DIR = normpath(joinpath(dirname(@__FILE__), "..", "tzfile"))

testnames = [
    "Africa/Abidjan",
    "America/Argentina/Buenos_Aires",
    "Africa/Dar_es_Salaam",
    "America/Port-au-Prince",
    "WET"
]

withenv("TZ" => nothing) do
    for testname in testnames

        # Determine timezone via systemsetup (Mac).
        mock_readall(cmd) = "Time Zone:  $testname\n"
        patches = [
            Patch(Base, :readall, mock_readall)
        ]
        patch(patches) do
            @test TimeZones._get_localzone_mac().name == TimeZone(testname).name
        end

        # Determine timezone from /etc/localtime (Mac).
        mock_readall(cmd) = ""
        mock_readlink(filename) = "/usr/share/zoneinfo/$testname"
        patches = [
            Patch(Base, :readall, mock_readall)
            Patch(Base, :readlink, mock_readlink)
        ]
        patch(patches) do
            @test TimeZones._get_localzone_mac().name == TimeZone(testname).name
        end

        # Determine timezone from /etc/timezone (Unix).
        mock_isfile(filename) = filename == "/etc/timezone" || contains(filename, PKG_DIR)
        mock_open(filename) = IOBuffer("$testname #Works with comments\n")
        mock_open(filename, arg) = Base.open(filename, arg)
        patches = [
            Patch(Base, :isfile, mock_isfile)
            Patch(Base, :open, mock_open)
        ]
        patch(patches) do
            #@test TimeZones._get_localzone_unix().name == TimeZone(testname).name
        end

        # Determine timezone from /etc/conf.d/clock (Unix).
        mock_isfile(filename) = filename == "/etc/conf.d/clock" || contains(filename, PKG_DIR)
        mock_open(filename) = IOBuffer("\n\nTIMEZONE=\"$testname\"")
        mock_open(filename, arg) = Base.open(filename, arg)
        patches = [
            Patch(Base, :isfile, mock_isfile)
            Patch(Base, :open, mock_open)
        ]
        patch(patches) do
            #@test TimeZones._get_localzone_unix().name == TimeZone(testname).name
        end

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
            @test TimeZones._get_localzone_unix().name == TimeZone(testname).name
        end

        # Unable to determine timezone (Unix).
        mock_isfile(filename) = false || contains(filename, PKG_DIR)
        mock_islink(filename) = false
        patches = [
            Patch(Base, :isfile, mock_isfile)
            Patch(Base, :islink, mock_islink)
        ]
        patch(patches) do
            @test_throws ErrorException TimeZones._get_localzone_unix()
        end

        # Test TZ environmental variable.
        withenv("TZ" => ":$testname") do
            @test TimeZones._get_localzone_unix().name == TimeZone(testname).name
        end

        withenv("TZ" => "") do
            @test_throws ErrorException TimeZones._get_localzone_unix()
        end
    end
end

# Test TZ environmental variables (Unix).
withenv("TZ" => ":bad") do
    @test_throws ErrorException TimeZones._get_localzone_unix()
end
withenv("TZ" => "") do
    @test_throws ErrorException TimeZones._get_localzone_unix()
end

# Reading a tzinfo file in "TZ"
withenv("TZ" => joinpath(TZFILE_DIR, "Warsaw")) do
    timezone = TimeZones._get_localzone_unix()
    @test string(timezone) == "local"
    @test length(timezone.transitions) == 167
    transition = timezone.transitions[166]
    @test transition.utc_datetime == Dates.DateTime(2037, 03, 29, 1)
    @test string(transition.zone.name) == "CEST"
    @test transition.zone.offset.dst == Dates.Second(3600)
    @test transition.zone.offset.utc == Dates.Second(3600)
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
#        timezone = TimeZones._get_localzone_unix()
#        @test string(timezone) == "local"
#        @test length(timezone.transitions) == 167
#        transition = timezone.transitions[166]
#        @test transition.utc_datetime == Dates.DateTime(2037, 03, 29, 1)
#        @test string(transition.zone.name) == "CEST"
#        @test transition.zone.offset.dst == Dates.Second(3600)
#        @test transition.zone.offset.utc == Dates.Second(3600)
#    end
#end

# Test Windows
if OS_NAME == :Windows
    mock_readall(args) = "Central Standard Time\r\n"
    patches = [
        Patch(Base, :readall, mock_readall)
    ]
    patch(patches) do
        @test string(TimeZones._get_localzone_windows()) == "America/Chicago"
    end
end
