module Casm.Run.Base where

import Base
import Data.Aeson
import Juvix.Compiler.Casm.Data.Builtins
import Juvix.Compiler.Casm.Data.Result qualified as Casm
import Juvix.Compiler.Casm.Error
import Juvix.Compiler.Casm.Extra.InputInfo
import Juvix.Compiler.Casm.Interpreter
import Juvix.Compiler.Casm.Translation.FromSource
import Juvix.Compiler.Casm.Validate
import Juvix.Data.Field
import Juvix.Data.PPOutput
import Juvix.Parser.Error

casmRunVMExitCode' :: Path Abs Dir -> Path Abs File -> Maybe (Path Abs File) -> IO ExitCode
casmRunVMExitCode' dirPath outputFile inputFile = do
  let args = maybe [] (\f -> ["--program_input", toFilePath f]) inputFile
  readProcessExitCodeCwd (toFilePath dirPath) "run_cairo_vm.sh" (toFilePath outputFile : args) ""

casmRunVM' :: Path Abs Dir -> Path Abs File -> Maybe (Path Abs File) -> IO Text
casmRunVM' dirPath outputFile inputFile = do
  let args = maybe [] (\f -> ["--program_input", toFilePath f]) inputFile
  readProcessCwd (toFilePath dirPath) "run_cairo_vm.sh" (toFilePath outputFile : args) ""

cairoVmPrecondition :: Assertion
cairoVmPrecondition = do
  assertCmdExists $(mkRelFile "run_cairo_vm.sh")

casmRunVMError :: EntryPoint -> LabelInfo -> Code -> [Builtin] -> Int -> Maybe (Path Abs File) -> (String -> IO ()) -> Assertion
casmRunVMError entryPoint labi instrs blts outputSize inputFile step = do
  withTempDir'
    ( \dirPath -> do
        step "Serialize to Cairo bytecode"
        let res =
              run
                . runReader entryPoint
                $ casmToCairo
                  Casm.Result
                    { _resultLabelInfo = labi,
                      _resultCode = instrs,
                      _resultBuiltins = blts,
                      _resultOutputSize = outputSize
                    }
            outputFile = dirPath <//> $(mkRelFile "out.json")
        encodeFile (toFilePath outputFile) res
        step "Run Cairo VM"
        exitCode <- casmRunVMExitCode' dirPath outputFile inputFile
        case exitCode of
          ExitSuccess -> assertFailure "expected error"
          ExitFailure _ -> return ()
    )

casmRunVM :: EntryPoint -> LabelInfo -> Code -> [Builtin] -> Int -> Maybe (Path Abs File) -> Path Abs File -> (String -> IO ()) -> Assertion
casmRunVM entryPoint labi instrs blts outputSize inputFile expectedFile step = do
  withTempDir'
    ( \dirPath -> do
        step "Serialize to Cairo bytecode"
        let res =
              run
                . runReader entryPoint
                $ casmToCairo
                  Casm.Result
                    { _resultLabelInfo = labi,
                      _resultCode = instrs,
                      _resultBuiltins = blts,
                      _resultOutputSize = outputSize
                    }
            outputFile = dirPath <//> $(mkRelFile "out.json")
        encodeFile (toFilePath outputFile) res
        step "Run Cairo VM"
        actualOutput <- casmRunVM' dirPath outputFile inputFile
        step "Compare expected and actual program output"
        expected <- readFile expectedFile
        assertEqDiffText ("Check: RUN output = " <> toFilePath expectedFile) actualOutput expected
    )

casmInterpret :: LabelInfo -> Code -> Maybe (Path Abs File) -> Path Abs File -> (String -> IO ()) -> Assertion
casmInterpret labi instrs inputFile expectedFile step =
  withTempDir'
    ( \dirPath -> do
        let outputFile = dirPath <//> $(mkRelFile "out.out")
        step "Interpret"
        hout <- openFile (toFilePath outputFile) WriteMode
        r' <- doRun hout labi instrs inputFile
        case r' of
          Left err -> do
            hClose hout
            assertFailure (prettyString err)
          Right value' -> do
            hPrint hout value'
            hClose hout
            actualOutput <- readFile outputFile
            step "Compare expected and actual program output"
            expected <- readFile expectedFile
            assertEqDiffText ("Check: RUN output = " <> toFilePath expectedFile) actualOutput expected
    )

casmRunAssertionError' ::
  EntryPoint ->
  LabelInfo ->
  Code ->
  [Builtin] ->
  Int ->
  Maybe (Path Abs File) ->
  (String -> IO ()) ->
  Assertion
casmRunAssertionError' entryPoint labi instrs blts outputSize inputFile step =
  case validate labi instrs of
    Left err -> do
      assertFailure (prettyString err)
    Right () -> do
      casmRunVMError entryPoint labi instrs blts outputSize inputFile step

casmRunAssertion' ::
  EntryPoint ->
  Bool ->
  Bool ->
  LabelInfo ->
  Code ->
  [Builtin] ->
  Int ->
  Maybe (Path Abs File) ->
  Path Abs File ->
  (String -> IO ()) ->
  Assertion
casmRunAssertion' entryPoint bInterp bRunVM labi instrs blts outputSize inputFile expectedFile step =
  case validate labi instrs of
    Left err -> do
      assertFailure (prettyString err)
    Right () -> do
      when bInterp $
        casmInterpret labi instrs inputFile expectedFile step
      when bRunVM $
        casmRunVM entryPoint labi instrs blts outputSize inputFile expectedFile step

casmRunAssertion :: Bool -> Bool -> Path Abs Dir -> Path Abs File -> Maybe (Path Abs File) -> Path Abs File -> (String -> IO ()) -> Assertion
casmRunAssertion bInterp bRunVM root mainFile inputFile expectedFile step = do
  step "Parse"
  r <- parseFile mainFile
  case r of
    Left err -> assertFailure (renderStringDefault err)
    Right (labi, instrs) -> do
      entryPoint <- testDefaultEntryPointIO root mainFile
      casmRunAssertion' entryPoint bInterp bRunVM labi instrs [] 1 inputFile expectedFile step

casmRunErrorAssertion :: Path Abs File -> (String -> IO ()) -> Assertion
casmRunErrorAssertion mainFile step = do
  step "Parse"
  r <- parseFile mainFile
  case r of
    Left _ -> assertBool "" True
    Right (labi, instrs) -> do
      step "Validate"
      case validate labi instrs of
        Left {} -> assertBool "" True
        Right () -> do
          step "Interpret"
          r' <- doRun stderr labi instrs Nothing
          case r' of
            Left _ -> assertBool "" True
            Right _ -> assertFailure "no error"

parseFile :: Path Abs File -> IO (Either ParserError (LabelInfo, Code))
parseFile f = do
  s <- readFile f
  return (runParser f s)

doRun ::
  Handle ->
  LabelInfo ->
  Code ->
  Maybe (Path Abs File) ->
  IO (Either CasmError FField)
doRun hout labi instrs inputFile = do
  inputInfo <- readInputInfo inputFile
  catchRunErrorIO (hRunCode hout inputInfo labi instrs)
