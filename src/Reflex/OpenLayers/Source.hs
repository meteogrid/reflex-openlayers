{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE JavaScriptFFI #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Reflex.OpenLayers.Source (
    Source (..)
  , Tile
  , Image
  , Raster
  , Vector
  , RasterOperation (..)
  , HasUrl (..)
  , HasFormat (..)
  , FeatureLoader (..)
  , FeatureFormat (..)
  , Pixel
  , red
  , green
  , blue
  , alpha

  , imageWMS
  , imageWMS'
  , tileWMS
  , tileWMS'
  , tileXYZ
  , tileXYZ'
  , osm
  , raster
  , vector
  , someSource

  , featureCollection
  , featureLoader

  , mkSource -- internal
) where

import Reflex
import Reflex.Dom
import Reflex.OpenLayers.Util
import Reflex.OpenLayers.Event
import Reflex.OpenLayers.Collection
import Reflex.OpenLayers.Projection

import Data.Aeson
import Data.Aeson.Types (parseMaybe)
import Data.Proxy
import Data.Word (Word8)
import Data.Default(Default(..))
import Data.Text (Text)
import qualified Data.Map as M
import Control.Lens
import Control.Monad.IO.Class (liftIO)
import GHCJS.Marshal.Pure (PToJSVal(pToJSVal), PFromJSVal)
import GHCJS.Marshal (ToJSVal(toJSVal), FromJSVal(fromJSVal))
import GHCJS.Types (JSVal, IsJSVal, jsval)
import GHCJS.Foreign.QQ
import GHCJS.Foreign.Callback
import Sigym4.Geometry hiding (Raster, Pixel)

data TileK = TileK | ImageK
type Tile = 'TileK
type Image = 'ImageK

data SourceK = RasterK | VectorK
type Raster = 'RasterK
type Vector = 'VectorK

class RasterOperation f s | f->s, s->f where
  applyOp       :: f -> JSVal -> IO JSVal
  packSources   :: MonadWidget t m => s -> m JSVal
  operationType :: f -> Text

data Source (r::SourceK) (k::TileK) t crs where
  ImageWMS :: {
      _imageWmsUrl    :: Text
    , _imageWmsParams :: M.Map Text Text
    } -> Source Raster Image t crs

  TileWMS :: {
      _tileWmsUrl    :: Text
    , _tileWmsParams :: M.Map Text Text
    } -> Source Raster Tile t crs

  OSM :: Source Raster Tile t SphericalMercator

  TileXYZ :: {
      _tileXyzUrl        :: Text
    , _tileXyzPixelRatio :: Double
    , _tileXyzSize       :: (Int,Int)
    } -> Source Raster Tile t crs

  Raster :: RasterOperation o s => {
      _rasterOperation :: o
    , _rasterSources   :: s
    } -> Source Raster Image t crs

  VectorSource :: {
      _vectorFeatures  :: Maybe (Collection t key (Feature g a crs))
    , _vectorLoader    :: Maybe (FeatureLoader crs)
    } -> Source Vector Image t crs

data FeatureFormat crs
  = GeoJSON

instance Default (FeatureFormat crs) where
  def = GeoJSON

data FeatureLoader crs
  = FeatureLoader {
      _featureLoaderUrl    :: Text
    , _featureLoaderFormat :: FeatureFormat crs
    }
makeFields ''FeatureLoader

featureLoader :: Text -> FeatureLoader crs
featureLoader = flip FeatureLoader def



newtype JSSource = JSSource JSVal
  deriving (PToJSVal, PFromJSVal, ToJSVal, FromJSVal)
instance IsJSVal JSSource

someSource :: MonadWidget t m => WithSomeCrs (Source r k t) -> m JSSource
someSource = fmap JSSource . mkSource

newtype Pixel = Pixel JSVal deriving (PFromJSVal, PToJSVal)
red, green, blue, alpha :: Lens' Pixel Word8
red = lens (\p->[jsu'|$r=`p[0];|]) (\p v-> [jsu'|$r=`p;$r[0]=`v;|])
green = lens (\p->[jsu'|$r=`p[1];|]) (\p v-> [jsu'|$r=`p;$r[1]=`v;|])
blue = lens (\p->[jsu'|$r=`p[2];|]) (\p v-> [jsu'|$r=`p;$r[2]=`v;|])
alpha = lens (\p->[jsu'|$r=`p[3];|]) (\p v-> [jsu'|$r=`p;$r[3]=`v;|])



instance RasterOperation (Pixel -> Pixel) JSSource where
  applyOp f i = return (pToJSVal (f [jsu'|$r=`i[0];|]))
  packSources (JSSource s) = liftIO [jsu|$r=[`s];|]
  operationType _ = "pixel"




imageWMS
  :: Text -> M.Map Text Text -> WithSomeCrs (Source Raster Image t)
imageWMS = imageWMS' def

imageWMS'
  :: forall t. Projection -> Text -> M.Map Text Text
  -> WithSomeCrs (Source Raster Image t)
imageWMS' (Projection crs) serverUrl params =
  reifyCrs crs $ \(Proxy :: Proxy crs) ->
    WithSomeCrs (ImageWMS serverUrl params :: Source Raster Image t crs)

tileWMS
  :: Text -> M.Map Text Text -> WithSomeCrs (Source Raster Tile t)
tileWMS = tileWMS' def

tileWMS'
  :: forall t. Projection -> Text -> M.Map Text Text
  -> WithSomeCrs (Source Raster Tile t)
tileWMS' (Projection crs) serverUrl params =
  reifyCrs crs $ \(Proxy :: Proxy crs) ->
    WithSomeCrs (TileWMS serverUrl params :: Source Raster Tile t crs)

tileXYZ
  :: Text -> Double -> WithSomeCrs (Source Raster Tile t)
tileXYZ serverUrl scaleFactor = tileXYZ' def serverUrl scaleFactor (256, 256)

tileXYZ'
  :: forall t. Projection -> Text -> Double -> (Int, Int)
  -> WithSomeCrs (Source Raster Tile t)
tileXYZ' (Projection crs) serverUrl scale size =
  reifyCrs crs $ \(Proxy :: Proxy crs) ->
    WithSomeCrs (TileXYZ serverUrl scale size :: Source Raster Tile t crs)

osm :: WithSomeCrs (Source Raster Tile t)
osm = WithSomeCrs OSM


raster :: RasterOperation o s => o -> s -> WithSomeCrs (Source Raster Image t)
raster = raster' def

raster'
  :: forall o s t. RasterOperation o s
  => Projection -> o -> s -> WithSomeCrs (Source Raster Image t)
raster' (Projection crs) operation s =
  reifyCrs crs $ \(Proxy :: Proxy crs) ->
    WithSomeCrs (Raster operation s :: Source Raster Image t crs)


vector
  :: KnownCrs crs
  => proxy crs
  -> Maybe (Collection t key (Feature g a crs))
  -> Maybe (FeatureLoader crs)
  -> WithSomeCrs (Source Vector Image t)
vector _ col loader = WithSomeCrs (VectorSource col loader)

mkSource :: MonadWidget t m => WithSomeCrs (Source r k t) -> m JSVal
mkSource (WithSomeCrs (s :: Source r k t crs)) = do
  case s of
    ImageWMS{_imageWmsUrl, _imageWmsParams} -> do
      proj <- toJSVal_projection (Projection (reflectCrs (Proxy :: Proxy crs)))
      let params = map_toJSVal _imageWmsParams
      liftIO [jsu|
        $r=new ol.source.ImageWMS(
          {url:`_imageWmsUrl, params:`params, projection:`proj});|]

    TileWMS{_tileWmsUrl, _tileWmsParams} -> do
      proj <- toJSVal_projection (Projection (reflectCrs (Proxy :: Proxy crs)))
      let params = map_toJSVal _tileWmsParams
      liftIO [jsu|
        $r=new ol.source.TileWMS(
          {url:`_tileWmsUrl, params:`params, projection:`proj});|]

    TileXYZ{_tileXyzUrl, _tileXyzPixelRatio, _tileXyzSize=(w,h)} -> do
      proj <- toJSVal_projection (Projection (reflectCrs (Proxy :: Proxy crs)))
      liftIO [jsu|
        $r=new ol.source.XYZ(
          { url:`_tileXyzUrl
          , tileSize: [`w, `h]
          , tilePixelRatio: `_tileXyzPixelRatio
          , projection:`proj
          });|]

    OSM{} -> liftIO [jsu|$r=new ol.source.OSM();|]

    Raster{_rasterSources, _rasterOperation} -> do
      sources <- packSources _rasterSources
      liftIO $ do
        let typ = operationType _rasterOperation
        cb <- fmap jsval $ syncCallback1' (applyOp _rasterOperation)
        -- TODO Release callback on gc
        [jsu|$r=new ol.source.Raster({ sources:`sources
                                     , operation:`cb
                                     , threads: 0
                                     , operationType: `typ});|]

    VectorSource{_vectorFeatures, _vectorLoader} -> do
      proj <- toJSVal_projection (Projection (reflectCrs (Proxy :: Proxy crs)))
      liftIO $ do
        opts :: JSVal <- [jsu|$r={projection:`proj};|]
        case _vectorFeatures of
          Just fs -> [jsu_|`opts['features']=`fs;|]
          Nothing -> return()
        case _vectorLoader of
          Just loader -> do
            case loader^.format of
              GeoJSON ->
                [jsu_|`opts['format']=new ol.format.GeoJSON({
                  defaultDataProjection:`proj});|]
            let u = loader^.url
            [jsu_|`opts['url']=`u;|]
          Nothing -> return()
        [jsu|$r=new ol.source.Vector(`opts);|]

featureCollection
  :: ( MonadWidget t m, Ord k, Enum k
     , FromFeatureProperties d, ToFeatureProperties d
     , FromJSON (g crs), ToJSON (g crs)
     )
  => M.Map k (Feature g d crs)
  -> Event t (M.Map k (Maybe (Feature g d crs)))
  -> m (Collection t k (Feature g d crs))
featureCollection =
  collectionWith toJSVal_feature fromJSVal_feature $ \(h,f) -> do
    geom :: JSVal <- liftIO [jsu|$r=`f.getGeometry();|]
    wrapOLEvent_ "change" geom $ do
      geom' <- [jsu|$r=`f.getGeometry();|]
      newGeom <- maybe (fail "could not read geometry") return
                  =<< fromJSVal_geometry geom'
      return $ h & geometry .~ newGeom

toJSVal_feature
  :: (ToJSON (g crs), ToFeatureProperties d) => Feature g d crs -> IO JSVal
toJSVal_feature f = do
  jsF <- toJSVal (toJSON f)
  [js|$r=(new ol.format.GeoJSON()).readFeature(`jsF);|]

fromJSVal_feature
  :: ( FromFeatureProperties d , FromJSON (g crs))
  => JSVal -> IO (Maybe (Feature g d crs))
fromJSVal_feature j = do
  geoJ <- [js|$r=(new ol.format.GeoJSON()).writeFeatureObject(`j);|]
  val <- fromJSVal geoJ
  return (val >>= parseMaybe parseJSON)

fromJSVal_geometry :: FromJSON g => JSVal -> IO (Maybe g)
fromJSVal_geometry j = do
  geoJ <- [js|$r=(new ol.format.GeoJSON()).writeGeometryObject(`j);|]
  val <- fromJSVal geoJ
  return (val >>= parseMaybe parseJSON)

makeFields ''Pixel
