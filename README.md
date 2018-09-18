## ECL Code Snippets

ECL stands for "Enterprise Control Language" and it is the language you use when
working with HPCC Systems' big data technology.  More information on the
technology can be found at https://hpccsystems.com.  The platform's Open Source
repo is at https://github.com/hpcc-systems/HPCC-Platform.

The code snippets here were useful to me at some time or another, and someone
may find them useful again.  Most are stand-alone functions, function macros, or
macros, meant to be used within a larger ECL program.  The code in the BWR
directory are executable scripts rather than libraries.  Most code is
well-commented.

## Snippet Categories

### Programming
* [BitSet.ecl](BitSet.ecl)
* [BlendJoin.ecl](BlendJoin.ecl)
* [BWR_InversionOfControlDemo.ecl](BWR/BWR_InversionOfControlDemo.ecl)
* [BWR_ShowPlatformConstants.ecl](BWR/BWR_ShowPlatformConstants.ecl)
* [NotifyHelper.ecl](NotifyHelper.ecl)
* [PlatformVersionCheck.ecl](PlatformVersionCheck.ecl)
* [Factorial.ecl](Factorial.ecl)
* [RandomFilename.ecl](RandomFilename.ecl)
* [ReadLocalConfigFile.ecl](ReadLocalConfigFile.ecl)
* [ReadLocalFile.ecl](ReadLocalFile.ecl)
* [RemoveAllSuperFileLogicalFiles.ecl](RemoveAllSuperFileLogicalFiles.ecl)
* [RowFieldsOut.ecl](RowFieldsOut.ecl)
* [ScalarArgType.ecl](ScalarArgType.ecl)
* [Sets.ecl](Sets.ecl)
* [Str.ecl](Str.ecl)
* [UUID.ecl](UUID.ecl)
* [WholeUpdate.ecl](WholeUpdate.ecl)

### Configuration
* [BWR_ShowInstalledPlugins.ecl](BWR/BWR_ShowInstalledPlugins.ecl)

### Transforming Data
* [AppendUniqueID.ecl](AppendUniqueID.ecl)
* [CleanBusinessName.ecl](CleanBusinessName.ecl)
* [ConvertTopLevelFieldsToNewDataType.ecl](ConvertTopLevelFieldsToNewDataType.ecl)
* [CreateNominalValues.ecl](CreateNominalValues.ecl)
* [ReplaceCharInDataset.ecl](ReplaceCharInDataset.ecl)

### Data Introspection
* [BWR\_FilePartAnalyzer.ecl](BWR/BWR_FilePartAnalyzer.ecl)
* [BWR\_RecordAllDataTypes.ecl](BWR/BWR_RecordAllDataTypes.ecl)

### Utilities
* [DataPull.ecl](DataPull.ecl)
* [WorkunitExec.ecl](WorkunitExec.ecl)
