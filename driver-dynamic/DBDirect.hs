-----------------------------------------------------------
-- |
-- Module      :  Main
-- Copyright   :  Daan Leijen (c) 1999, daan@cs.uu.nl
--                HWT Group (c) 2003,
--                Bjorn Bringert (c) 2005-2006, bjorn@bringert.net
-- License     :  BSD-style
-- 
-- Maintainer  :  haskelldb-users@lists.sourceforge.net
-- Stability   :  experimental
-- Portability :  portable
--
-- DBDirect generates a Haskell module from a database.
-- It first reads the system catalog of the database into
-- a 'Catalog' data type. After that it pretty prints that
-- data structure in an appropiate Haskell module which
-- can be used to perform queries on the database.
--
-----------------------------------------------------------

module Main where

import Data.List
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO

import Database.HaskellDB
import Database.HaskellDB.DynConnect
import Database.HaskellDB.DBSpec
import Database.HaskellDB.DBSpec.PPHelpers
import Database.HaskellDB.DBSpec.DBSpecToDBDirect

createModules m useBStrT db = 
    do
    putStrLn "Getting database info..."
    spec <- dbToDBSpec useBStrT m db
    putStrLn "Writing modules..."
    dbInfoToModuleFiles "." m spec

-- | Command line driver
main = do
       putStrLn "DB/Direct: Daan Leijen (c) 1999, HWT (c) 2003-2004,"
       putStrLn "           Bjorn Bringert (c) 2005-2006"
       putStrLn ""
       args <- getArgs
       let (flags,args') = partition ("-" `isPrefixOf`) args
           useBStrT = "-b" `elem` flags
       case args' of
                  [m,d,o] -> 
                      do
                      let opts = splitOptions o
		      putStrLn "Connecting to database..."
                      dynConnect_ d opts (createModules m useBStrT)
		      putStrLn "Done!"
                  _ -> 
                      do
                      showHelp
                      exitFailure

splitOptions :: String -> [(String,String)]
splitOptions = map (split2 '=') . split ','

split :: Char -> String -> [String]
split _ [] = []
split g xs = y : split g ys
  where (y,ys) = split2 g xs

split2 :: Char -> String -> (String,String)
split2 g xs = (ys, drop 1 zs)
  where (ys,zs) = break (==g) xs

-- | Shows usage information
showHelp = mapM_ (hPutStrLn stderr) t
    where
    t = ["Usage: DBDirect [-b] <module> <driver> <options>",
         "",
         "-b         Use bounded string types",
         "<driver>   One of: WX, HSQL.MySQL, HDBC.PostgreSQL, etc",
         "<options>  Driver dependent,e.g.",
         "           WX:              dsn=<dsn>,uid=<uid>,pwd=<pwd>",
         "           HSQL.MySQL:      server=<server>,db=<db>,uid=<uid>,pwd=<pwd>",
         "           HDBC.PostgreSQL: host=<server>,dbname=<db>,user=<uid>,password=<pwd>"]
