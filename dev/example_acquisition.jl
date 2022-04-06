using Medipix
using ExcelFiles
using DataFrames

# df = DataFrame(load("/Users/chen/.julia/dev/Medipix/src/merlin_commands.xlsx", "Example"))

@medipix "GET"	"DETECTORSTATUS"
@medipix "SET/GET"	"CONTINUOUSRW"
@medipix "CMD"	"ABORT"
@medipix "SET/GET"	"ACQUISITIONTIME"
@medipix "SET/GET"	"COUNTERDEPTH"
@medipix "SET/GET"	"NUMFRAMESTOACQUIRE"
@medipix "SET/GET"	"NUMFRAMESPERTRIGGER"
@medipix "SET/GET"	"FILEFORMAT"
@medipix "SET/GET"	"IMAGESPERFILE"
@medipix "SET/GET"	"FILEENABLE"
@medipix "SET/GET"	"USETIMESTAMPING"
@medipix "SET/GET"	"FILEFORMAT"
@medipix "SET/GET"	"FILEDIRECTORY"
@medipix "SET/GET"	"TRIGGERSTART"
@medipix "SET/GET"	"TRIGGERSTOP"
@medipix "SET/GET"	"TriggerOutTTL"
@medipix "SET/GET"	"TriggerOutTTLInvert"
@medipix "SET/GET"	"TriggerInTTLDelay"
@medipix "CMD"	"STARTACQUISITION"
@medipix "CMD"	"STOPACQUISITION"
@medipix "SET/GET"	"FILENAME"