module Distribution.Client.Patch
  ( patchedTarPackageCabalFile
  , patchedExtractTarGzFile
  , patchedPackageCabalFile
  )
where

import Distribution.Package
import Distribution.Simple.Program
import Distribution.Simple.Utils
import Distribution.Version
import Distribution.Verbosity

import Distribution.Client.Tar

import Control.Monad
import System.FilePath
import System.Directory

import qualified Data.ByteString.Lazy as BS

patchedPackageCabalFile :: PackageIdentifier
                        -> IO FilePath
                        -> IO (Maybe BS.ByteString)
patchedPackageCabalFile
  (PackageIdentifier
    { pkgName = name
    , pkgVersion = version }) patchesDir
  = findCabalFilePatch (unPackageName name
                      ++ "-"
                      ++ (intercalate "." $ map show (versionNumbers version))
                      <.> "cabal") patchesDir

patchedTarPackageCabalFile :: FilePath
                           -> IO FilePath
                           -> IO (Maybe (FilePath, BS.ByteString))
patchedTarPackageCabalFile tarFilePath patchesDir' =
  fmap (fmap (\bs -> (cabalFile, bs))) $ findCabalFilePatch cabalFile patchesDir'
  where packageAndVersion = dropExtension . dropExtension $ tarFilePath
        cabalFile = packageAndVersion <.> "cabal"

findCabalFilePatch :: FilePath
                   -> IO FilePath -- ^ Filepath of the patches directory
                   -> IO (Maybe BS.ByteString)
findCabalFilePatch cabalFile patchesDir' = do
  patchesDir <- patchesDir'
  -- TODO: Speed this up with a cache?
  let cabalPatchLocation = patchesDir </> "patches" </> cabalFile
  exists <- doesFileExist cabalPatchLocation
  if exists
  then fmap Just $ BS.readFile cabalPatchLocation
  else return Nothing

patchedExtractTarGzFile :: Verbosity
                        -> Bool     -- ^ Setup for patching?
                        -> FilePath -- ^ Destination directory of tar.gz file
                        -> FilePath -- ^ Expected subdir (to check for tarbombs)
                        -> FilePath -- ^ Tarball
                        -> IO FilePath -- ^ Filepath of the patches directory
                        -> Bool        -- ^ Is git repo
                        -> IO ()
patchedExtractTarGzFile verbosity setupForPatch dir expected tar patchesDir' isGit = do
  patchesDir <- patchesDir'
  -- TODO: Speed this up with a cache?
  let patchFileLocation = patchesDir </> "patches" </> patchFile
  exists <- doesFileExist patchFileLocation
  if isGit
  then copyDirectoryRecursive verbosity tar dir
  else extractTarGzFile dir expected tar
  when exists $ do
    (gitProg, _, _) <- requireProgramVersion verbosity
                      gitProgram
                      (orLaterVersion (mkVersion [1,8,5]))
                      defaultProgramDb
    let runGit :: [String] -> IO String
        runGit = getProgramInvocationOutput verbosity . programInvocation gitProg
    let gitDir = dir </> expected
    notice verbosity $ "Found patch in eta-hackage for " ++ expected
    _ <- runGit ["-C", gitDir, "init"]
    when setupForPatch $ do
      _ <- runGit ["-C", gitDir, "add", "."]
      _ <- runGit ["-C", gitDir, "commit", "-m", "First"]
      return ()
    _ <- runGit ["-C", gitDir, "apply",
                 "--ignore-space-change", "--ignore-whitespace"
           , patchFileLocation]
    when setupForPatch $ do
      _ <- runGit ["-C", gitDir, "add", "."]
      return ()
  where packageAndVersion = takeFileName expected
        patchFile = packageAndVersion <.> "patch"
