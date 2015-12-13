{-# LANGUAGE OverloadedStrings #-}
{-

Copyright 2012, 2013, 2014 Colin Woodbury <colingw@gmail.com>

This file is part of Aura.

Aura is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Aura is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Aura.  If not, see <http://www.gnu.org/licenses/>.

-}

module Aura.Settings.Enable
    ( getSettings
    , debugOutput ) where

import System.Environment (getEnvironment)
import Data.Maybe         (fromMaybe)
import Data.Monoid
import Data.Foldable
import qualified Data.Text as T

import Aura.Languages (Language, langFromEnv)
import Aura.MakePkg   (makepkgConfFile)
import Aura.Settings.Base
import Aura.Pacman
import Aura.Flags

import Utilities (ifte_)
import Shell
import Shelly
import Prelude hiding (FilePath)

---

getSettings :: Maybe Language -> ([Flag], [String], [String]) -> Sh Settings
getSettings lang (auraFlags, input, pacOpts) = do
  confFile    <- getPacmanConf
  environment <- liftIO getEnvironment
  pmanCommand <- getPacmanCmd environment $ noPowerPillStatus auraFlags
  makepkgConf <- getConf $ fromText makepkgConfFile
  buildPath'  <- checkBuildPath (buildPath auraFlags) (getCachePath confFile)
  let language   = checkLang lang environment
      buildUser' = fromMaybe (T.pack $ getTrueUser environment) (buildUser auraFlags)
  pure Settings { inputOf         = input
                , pacOptsOf       = pacOpts
                , otherOptsOf     = show <$> auraFlags
                , environmentOf   = environment
                , buildUserOf     = buildUser'
                , langOf          = language
                , pacmanCmdOf     = fromText pmanCommand
                , editorOf        = getEditor environment
                , carchOf         = singleEntry makepkgConf "CARCH"
                                    "COULDN'T READ $CARCH"
                , ignoredPkgsOf   = getIgnoredPkgs confFile <>
                                    ignoredAuraPkgs auraFlags
                , makepkgFlagsOf  = makepkgFlags auraFlags
                , buildPathOf     = buildPath'
                , cachePathOf     = getCachePath confFile
                , logFilePathOf   = getLogFilePath confFile
                , sortSchemeOf    = sortSchemeStatus auraFlags
                , truncationOf    = truncationStatus auraFlags
                , beQuiet         = quietStatus auraFlags
                , suppressMakepkg = suppressionStatus auraFlags
                , delMakeDeps     = delMakeDepsStatus auraFlags
                , mustConfirm     = confirmationStatus auraFlags
                , neededOnly      = neededStatus auraFlags
                , mayHotEdit      = hotEditStatus auraFlags
                , diffPkgbuilds   = pbDiffStatus auraFlags
                , rebuildDevel    = rebuildDevelStatus auraFlags
                , useCustomizepkg = customizepkgStatus auraFlags
                , noPowerPill     = noPowerPillStatus auraFlags
                , keepSource      = keepSourceStatus auraFlags
                , buildABSDeps    = buildABSDepsStatus auraFlags
                , dryRun          = dryRunStatus auraFlags }

debugOutput :: Settings -> IO ()
debugOutput ss = do
  let yn a = if a then "Yes!" else "No."
      env  = environmentOf ss
  traverse_ putStrLn [ "User              => " <> getUser' env
                     , "True User         => " <> getTrueUser env
                     , "Build User        => " <> show (buildUserOf ss)
                     , "Using Sudo?       => " <> yn (varExists "SUDO_USER" env)
                     , "Pacman Flags      => " <> unwords (pacOptsOf ss)
                     , "Other Flags       => " <> unwords (otherOptsOf ss)
                     , "Other Input       => " <> unwords (inputOf ss)
                     , "Language          => " <> show (langOf ss)
                     , "Pacman Command    => " <> show (pacmanCmdOf ss)
                     , "Editor            => " <> editorOf ss
                     , "$CARCH            => " <> show (carchOf ss)
                     , "Ignored Pkgs      => " <> show (T.unwords (ignoredPkgsOf ss))
                     , "Build Path        => " <> show (buildPathOf ss)
                     , "Pkg Cache Path    => " <> show (cachePathOf ss)
                     , "Log File Path     => " <> show (logFilePathOf ss)
                     , "Quiet?            => " <> yn (beQuiet ss)
                     , "Silent Building?  => " <> yn (suppressMakepkg ss)
                     , "Must Confirm?     => " <> yn (mustConfirm ss)
                     , "Needed only?      => " <> yn (neededOnly ss)
                     , "PKGBUILD editing? => " <> yn (mayHotEdit ss)
                     , "Diff PKGBUILDs?   => " <> yn (diffPkgbuilds ss)
                     , "Rebuild Devel?    => " <> yn (rebuildDevel ss)
                     , "Use Customizepkg? => " <> yn (useCustomizepkg ss)
                     , "Forego PowerPill? => " <> yn (noPowerPill ss)
                     , "Keep source?      => " <> yn (keepSource ss) ]

checkLang :: Maybe Language -> Environment -> Language
checkLang Nothing env   = langFromEnv $ T.pack $ getLangVar env
checkLang (Just lang) _ = lang

-- | Defaults to the cache path if no (legal) build path was given.
checkBuildPath :: FilePath -> FilePath -> Sh FilePath
checkBuildPath bp bp' = ifte_ bp bp' <$> test_e bp
