module Commands.Compile.Anoma where

import Commands.Base
import Commands.Compile.Anoma.Options
import Commands.Extra.NewCompile
import Data.HashMap.Strict qualified as HashMap
import Juvix.Compiler.Nockma.Data.Module qualified as Nockma
import Juvix.Compiler.Nockma.Encoding qualified as Encoding
import Juvix.Compiler.Nockma.Pretty qualified as Nockma
import Juvix.Compiler.Pipeline.Modular

runCommand :: (Members AppEffects r) => AnomaOptions 'InputMain -> Sem r ()
runCommand opts@AnomaOptions {..} = do
  let copts = opts ^. anomaCompileCommonOptions
      inputFile = copts ^. compileInputFile
      moutputFile = copts ^. compileOutputFile
  nockmaFile :: Path Abs File <- getOutputFile FileExtNockma inputFile moutputFile
  copts' <- fromCompileCommonOptionsMain _anomaCompileCommonOptions
  let opts' = AnomaOptions {_anomaCompileCommonOptions = copts', ..}
  if
      | _anomaModular -> do
          (mid, mtab) <- runPipelineModular opts' (Just (copts' ^. compileInputFile)) Nothing modularCoreToAnoma
          outputAnomaModuleTable opts (copts' ^. compileDebug) nockmaFile mid mtab
      | otherwise -> do
          r <- runError @JuvixError $ runPipeline opts' (_anomaCompileCommonOptions ^. compileInputFile) upToAnoma
          res <- getRight r
          outputAnomaModule opts (copts' ^. compileDebug) nockmaFile res

outputAnomaModule :: (Members '[EmbedIO, App, Files] r) => AnomaOptions i -> Bool -> Path Abs File -> Nockma.Module -> Sem r ()
outputAnomaModule opts debugOutput nockmaFile Nockma.Module {..} = do
  let code = fromJust (_moduleInfoTable ^. Nockma.infoCode)
      code' = Encoding.jamToByteString code
      prettyNockmaFile = replaceExtensions' nockmaDebugFileExts nockmaFile
      textNockmaFile = replaceExtensions' nockmaTextFileExts nockmaFile
      hoonFile = replaceExtension' hoonFileExt nockmaFile
  writeFileBS nockmaFile code'
  when (opts ^. anomaOutputText) (writeFileEnsureLn textNockmaFile (Nockma.ppSerialize code))
  when (opts ^. anomaOutputHoon) (writeHoonFile hoonFile code)
  when debugOutput (writeFileEnsureLn prettyNockmaFile (Nockma.ppPrint code))

outputAnomaModuleTable :: (Members '[EmbedIO, App, Files] r) => AnomaOptions i -> Bool -> Path Abs File -> ModuleId -> Nockma.ModuleTable -> Sem r ()
outputAnomaModuleTable opts debugOutput nockmaFile mid mtab = do
  let md = Nockma.lookupModuleTable mtab mid
  outputAnomaModule opts debugOutput nockmaFile md
  let storageNockmaFile = replaceExtensions' nockmaStorageFileExts nockmaFile
      modulesJammed =
        map Nockma.getModuleJammedCode
          . HashMap.elems
          $ mtab ^. Nockma.moduleTable
      modulesTerms = map (Nockma.TermAtom . Encoding.byteStringToAtom') modulesJammed
      modules = Nockma.makeList modulesTerms
  writeFileBS storageNockmaFile (Encoding.jamToByteString modules)

writeHoonFile :: (Members '[EmbedIO, App, Files] r) => Path Abs File -> Nockma.Term Natural -> Sem r ()
writeHoonFile hoonFile code = do
  let hoonCode = ".*(" <> Nockma.ppNock code <> " [9 2 0 1])"
  writeFileEnsureLn hoonFile hoonCode
