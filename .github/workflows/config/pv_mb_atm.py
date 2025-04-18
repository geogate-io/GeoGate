# script-version: 2.0
# Catalyst state generated using paraview version 5.13.0
import paraview
paraview.compatibility.major = 5
paraview.compatibility.minor = 13

#### import the simple module from the paraview
from paraview.simple import *
#### disable automatic camera reset on 'Show'
paraview.simple._DisableFirstRenderCameraReset()

# ----------------------------------------------------------------
# setup views used in the visualization
# ----------------------------------------------------------------

# get the material library
materialLibrary1 = GetMaterialLibrary()

# Create a new 'Render View'
renderView1 = CreateView('RenderView')
renderView1.ViewSize = [2044, 1302]
renderView1.AxesGrid = 'Grid Axes 3D Actor'
renderView1.StereoType = 'Crystal Eyes'
renderView1.CameraPosition = [-0.16211332172025042, 0.25506758626296133, 4.395632976067159]
renderView1.CameraFocalPoint = [0.08411377287113357, -0.13234382461630226, -2.2807087650193565]
renderView1.CameraViewUp = [0.0021926555986987763, 0.9983229181834788, -0.057849315389628925]
renderView1.CameraFocalDisk = 1.0
renderView1.CameraParallelScale = 1.7320439376202743
renderView1.LegendGrid = 'Legend Grid Actor'
renderView1.PolarGrid = 'Polar Grid Actor'
renderView1.BackEnd = 'OSPRay raycaster'
renderView1.OSPRayMaterialLibrary = materialLibrary1

SetActiveView(None)

# ----------------------------------------------------------------
# setup view layouts
# ----------------------------------------------------------------

# create new layout object 'Layout #1'
layout1 = CreateLayout(name='Layout #1')
layout1.AssignView(0, renderView1)
layout1.SetSize(2044, 1302)

# ----------------------------------------------------------------
# restore active view
SetActiveView(renderView1)
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# setup the data processing pipelines
# ----------------------------------------------------------------

# create a new 'XML MultiBlock Data Reader'
atm = XMLMultiBlockDataReader(registrationName='atm', FileName=['/Users/turuncu/Desktop/output/atm_000000.vtm', '/Users/turuncu/Desktop/output/atm_000001.vtm', '/Users/turuncu/Desktop/output/atm_000002.vtm', '/Users/turuncu/Desktop/output/atm_000003.vtm', '/Users/turuncu/Desktop/output/atm_000004.vtm', '/Users/turuncu/Desktop/output/atm_000005.vtm'])
atm.CellArrayStatus = ['element_mask', 'Sa_u10m', 'Sa_v10m']
atm.PointArrayStatus = ['longitude', 'latitude']

# ----------------------------------------------------------------
# setup the visualization in view 'renderView1'
# ----------------------------------------------------------------

# show data from atm
atmDisplay = Show(atm, renderView1, 'UnstructuredGridRepresentation')

# get 2D transfer function for 'Sa_u10m'
sa_u10mTF2D = GetTransferFunction2D('Sa_u10m')
sa_u10mTF2D.ScalarRangeInitialized = 1
sa_u10mTF2D.Range = [-20.0, 20.0, 0.0, 1.0]

# get color transfer function/color map for 'Sa_u10m'
sa_u10mLUT = GetColorTransferFunction('Sa_u10m')
sa_u10mLUT.TransferFunction2D = sa_u10mTF2D
sa_u10mLUT.RGBPoints = [-20.0, 0.231373, 0.298039, 0.752941, 0.0, 0.865003, 0.865003, 0.865003, 20.0, 0.705882, 0.0156863, 0.14902]
sa_u10mLUT.ScalarRangeInitialized = 1.0

# get opacity transfer function/opacity map for 'Sa_u10m'
sa_u10mPWF = GetOpacityTransferFunction('Sa_u10m')
sa_u10mPWF.Points = [-20.0, 0.0, 0.5, 0.0, 20.0, 1.0, 0.5, 0.0]
sa_u10mPWF.ScalarRangeInitialized = 1

# trace defaults for the display properties.
atmDisplay.Representation = 'Surface'
atmDisplay.ColorArrayName = ['CELLS', 'Sa_u10m']
atmDisplay.LookupTable = sa_u10mLUT
atmDisplay.SelectNormalArray = 'None'
atmDisplay.SelectTangentArray = 'None'
atmDisplay.SelectTCoordArray = 'None'
atmDisplay.TextureTransform = 'Transform2'
atmDisplay.OSPRayScaleArray = 'latitude'
atmDisplay.OSPRayScaleFunction = 'Piecewise Function'
atmDisplay.Assembly = 'Hierarchy'
atmDisplay.SelectedBlockSelectors = ['']
atmDisplay.SelectOrientationVectors = 'None'
atmDisplay.ScaleFactor = 0.1999995240354704
atmDisplay.SelectScaleArray = 'None'
atmDisplay.GlyphType = 'Arrow'
atmDisplay.GlyphTableIndexArray = 'None'
atmDisplay.GaussianRadius = 0.009999976201773519
atmDisplay.SetScaleArray = ['POINTS', 'latitude']
atmDisplay.ScaleTransferFunction = 'Piecewise Function'
atmDisplay.OpacityArray = ['POINTS', 'latitude']
atmDisplay.OpacityTransferFunction = 'Piecewise Function'
atmDisplay.DataAxesGrid = 'Grid Axes Representation'
atmDisplay.PolarAxes = 'Polar Axes Representation'
atmDisplay.ScalarOpacityFunction = sa_u10mPWF
atmDisplay.ScalarOpacityUnitDistance = 0.03421025527233762
atmDisplay.OpacityArrayName = ['POINTS', 'latitude']
atmDisplay.SelectInputVectors = [None, '']
atmDisplay.WriteLog = ''

# init the 'Piecewise Function' selected for 'OSPRayScaleFunction'
atmDisplay.OSPRayScaleFunction.Points = [-49.2702, 0.0, 0.5, 0.0, 52.2462, 1.0, 0.5, 0.0]

# init the 'Piecewise Function' selected for 'ScaleTransferFunction'
atmDisplay.ScaleTransferFunction.Points = [-90.125, 0.0, 0.5, 0.0, 90.125, 1.0, 0.5, 0.0]

# init the 'Piecewise Function' selected for 'OpacityTransferFunction'
atmDisplay.OpacityTransferFunction.Points = [-90.125, 0.0, 0.5, 0.0, 90.125, 1.0, 0.5, 0.0]

# setup the color legend parameters for each legend in this view

# get color legend/bar for sa_u10mLUT in view renderView1
sa_u10mLUTColorBar = GetScalarBar(sa_u10mLUT, renderView1)
sa_u10mLUTColorBar.Title = 'Sa_u10m'
sa_u10mLUTColorBar.ComponentTitle = ''

# set color bar visibility
sa_u10mLUTColorBar.Visibility = 1

# show color legend
atmDisplay.SetScalarBarVisibility(renderView1, True)

# ----------------------------------------------------------------
# setup color maps and opacity maps used in the visualization
# note: the Get..() functions create a new object, if needed
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# setup animation scene, tracks and keyframes
# note: the Get..() functions create a new object, if needed
# ----------------------------------------------------------------

# get time animation track
timeAnimationCue1 = GetTimeTrack()

# initialize the animation scene

# get the time-keeper
timeKeeper1 = GetTimeKeeper()

# initialize the timekeeper

# initialize the animation track

# get animation scene
animationScene1 = GetAnimationScene()

# initialize the animation scene
animationScene1.ViewModules = renderView1
animationScene1.Cues = timeAnimationCue1
animationScene1.AnimationTime = 0.0
animationScene1.EndTime = 216000.0
animationScene1.PlayMode = 'Snap To TimeSteps'

# ----------------------------------------------------------------
# setup extractors
# ----------------------------------------------------------------

# create extractor
pNG1 = CreateExtractor('PNG', renderView1, registrationName='PNG1')
# trace defaults for the extractor.
pNG1.Trigger = 'Time Step'

# init the 'PNG' selected for 'Writer'
pNG1.Writer.FileName = 'RenderView1_{timestep:06d}{camera}.png'
pNG1.Writer.ImageResolution = [2044, 1302]
pNG1.Writer.Format = 'PNG'

# ----------------------------------------------------------------
# restore active source
SetActiveSource(pNG1)
# ----------------------------------------------------------------

# ------------------------------------------------------------------------------
# Catalyst options
from paraview import catalyst
options = catalyst.Options()
options.ExtractsOutputDirectory = 'output'
options.GlobalTrigger = 'Time Step'
options.CatalystLiveTrigger = 'Time Step'

# ------------------------------------------------------------------------------
if __name__ == '__main__':
    from paraview.simple import SaveExtractsUsingCatalystOptions
    # Code for non in-situ environments; if executing in post-processing
    # i.e. non-Catalyst mode, let's generate extracts using Catalyst options
    SaveExtractsUsingCatalystOptions(options)
