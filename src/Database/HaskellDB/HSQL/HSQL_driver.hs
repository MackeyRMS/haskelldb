{-
 HSQL interface for HaskellDB

 TODO:
 - add Haddock comments
 - figure out date / time types
 - make odbcPrimQuery lazy
-}

module HSQL_driver (
		     hsqlConnect
		   , HSQL
		   ) where

import Data.Dynamic
import Maybe
import Monad

import Database
import Sql
import PrimQuery
import Query
import FieldType

import Database.HSQL as HSQL hiding (FieldDef)

type HSQL = Database Connection HSQLRow

data HSQLRow r = HSQLRow [(Attribute,HSQLValue)] deriving Show

type HSQLValue = Dynamic

-- Enable selection in an HSQL row
instance Typeable a => Row HSQLRow a where
    rowSelect = hsqlRowSelect

instance Typeable a => Row HSQLRow (Maybe a) where
    rowSelect = hsqlRowSelectMB

-- | Run an action on a HSQL Connection and close the connection.
hsqlConnect :: (opts -> IO Connection) -> opts -> (HSQL -> IO a) -> IO a
hsqlConnect connect opts action = 
    do
    conn <- handleSqlError (connect opts)
    x <- handleSqlError (action (newHSQL conn))
    disconnect conn
    return x

handleSqlError :: IO a -> IO a
handleSqlError io = handleSql (\err -> fail (show err)) io

newHSQL :: Connection -> HSQL
newHSQL connection
    = Database { dbQuery	= hsqlQuery,
    		 dbInsert	= hsqlInsert,
		 dbInsertNew 	= hsqlInsertNew,
		 dbDelete	= hsqlDelete,
		 dbUpdate	= hsqlUpdate,
		 dbTables       = hsqlTables,
		 dbDescribe     = hsqlDescribe,
		 database	= connection
	       }


hsqlRowSelect' :: (Typeable a, Typeable b) => Attr f r a -> HSQLRow r1 -> (Maybe b)
hsqlRowSelect' attr (HSQLRow vals)
        = case lookup (attributeName attr) vals of
            Nothing  -> error "Query.rowSelect: invalid attribute used ??"
            Just dyn -> case fromDynamic dyn of
	                  Nothing -> 
			      error ("Query.rowSelect: type mismatch: " 
				     ++ attributeName attr ++ " :: " ++ show dyn)
			  Just val -> val

hsqlRowSelectMB :: Typeable a => Attr f r (Maybe a) -> HSQLRow r -> (Maybe a)
hsqlRowSelectMB = hsqlRowSelect'

hsqlRowSelect :: Typeable a => Attr f r a -> HSQLRow r -> a
hsqlRowSelect attr vals = case (hsqlRowSelect' attr vals) of
			    Nothing -> error ("Query.rowSelect: Null returned from non-nullable field")
			    Just val -> val

hsqlInsertNew conn table assoc = 
    hsqlPrimExecute conn $ show $ ppInsert $ toInsertNew table assoc
	  
hsqlInsert conn table assoc = 
    hsqlPrimExecute conn $ show $ ppInsert $ toInsert table assoc
	  
hsqlDelete conn table exprs = 
    hsqlPrimExecute conn $ show $ ppDelete $ toDelete table exprs

hsqlUpdate conn table criteria assigns = 
    hsqlPrimExecute conn $ show $ ppUpdate $ toUpdate table criteria assigns

hsqlQuery :: Connection -> PrimQuery -> Rel r -> IO [HSQLRow r]
hsqlQuery connection qtree rel
    = do
      rows <- hsqlPrimQuery connection sql scheme rel
      -- FIXME: remove
      --putStrLn (unlines (map show rows))
      return rows
    where
      sql = show (ppSql (toSql qtree))  
      scheme = attributes qtree

hsqlTables :: Connection -> IO [TableName]
hsqlTables = HSQL.tables

hsqlDescribe :: Connection -> TableName -> IO [(Attribute,FieldDef)]
hsqlDescribe conn table = liftM (map toFieldDef) (HSQL.describe conn table)
    where
    toFieldDef (name,sqlType,nullable) = (name,(toFieldType sqlType, nullable))

toFieldType :: SqlType -> FieldType
toFieldType (SqlDecimal _ _) = DoubleT
toFieldType (SqlNumeric _ _) = DoubleT
toFieldType SqlSmallInt      = IntT
toFieldType SqlInteger       = IntT
toFieldType SqlReal          = DoubleT
toFieldType SqlFloat         = DoubleT
toFieldType SqlDouble        = DoubleT
--toFieldType SqlBit           = ?
toFieldType SqlTinyInt       = IntT
toFieldType SqlBigInt        = IntegerT
--toFieldType SqlDate          = ?
--toFieldType SqlTime          = ?
--toFieldType SqlTimeStamp     = ?
toFieldType _                = StringT


-----------------------------------------------------------
-- Primitive Query
-- The "Rel r" argument is a phantom argument to get
-- the return type right.
-----------------------------------------------------------

hsqlPrimQuery :: Connection -> String -> Scheme -> Rel r -> IO [HSQLRow r]
hsqlPrimQuery connection sql scheme _ = 
    do
    -- FIXME: (DEBUG) remove
    --putStrLn sql
    stmt <- HSQL.query connection sql
    -- FIXME: (DEBUG) remove
    -- putStrLn $ unlines $ map show $ getFieldsTypes stmt
    collectRows (getRow scheme) stmt

getRow :: Scheme -> Statement -> IO (HSQLRow r)
getRow scheme stmt = 
    do
    vals <- mapM (getField stmt) scheme
    return (HSQLRow (zip scheme vals))

getField :: Statement -> Attribute -> IO HSQLValue
getField s n = 
    case toFieldType t of
	    StringT  -> toVal (getFieldValueMB s n :: IO (Maybe String))
	    IntT     -> toVal (getFieldValueMB s n :: IO (Maybe Int))
	    IntegerT -> toVal (getFieldValueMB s n :: IO (Maybe Integer))
	    DoubleT  -> toVal (getFieldValueMB s n :: IO (Maybe Double))
    where
    (t,_) = getFieldValueType s n
    toVal :: Typeable a => IO (Maybe a) -> IO HSQLValue
    toVal = liftM toDyn

hsqlPrimExecute :: Connection -> String -> IO ()
hsqlPrimExecute connection sql = 
    do
    -- FIXME: (DEBUG) remove
    --putStrLn sql
    execute connection sql