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
renderView1.ViewSize = [2044, 1456]
renderView1.AxesGrid = 'Grid Axes 3D Actor'
renderView1.CenterOfRotation = [-0.0038920044898986816, 0.017802953720092773, -0.0031360387802124023]
renderView1.StereoType = 'Crystal Eyes'
renderView1.CameraPosition = [0.25587414979580486, -4.026285264245448, 2.3281029127046344]
renderView1.CameraFocalPoint = [-0.0038920044898986834, 0.017802953720092773, -0.003136038780212402]
renderView1.CameraViewUp = [-0.0727042454194824, 0.4945877833454674, 0.8660814149162889]
renderView1.CameraFocalDisk = 1.0
renderView1.CameraParallelScale = 1.771578048506157
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
layout1.SetSize(2044, 1456)

# ----------------------------------------------------------------
# restore active view
SetActiveView(renderView1)
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# setup the data processing pipelines
# ----------------------------------------------------------------

# create a new 'XML PolyData Reader'
world_coastlines_and_lakesvtp = XMLPolyDataReader(registrationName='world_coastlines_and_lakes.vtp', FileName=['world_coastlines_and_lakes.vtp'])
world_coastlines_and_lakesvtp.CellArrayStatus = ['plates']
world_coastlines_and_lakesvtp.TimeArray = 'None'

# create a new 'XML Partitioned Dataset Reader'
ocn = XMLPartitionedDatasetReader(registrationName='ocn', FileName=['/Users/turuncu/Desktop/untitled folder/datasets/ocn_000000.vtpd', '/Users/turuncu/Desktop/untitled folder/datasets/ocn_000001.vtpd', '/Users/turuncu/Desktop/untitled folder/datasets/ocn_000002.vtpd', '/Users/turuncu/Desktop/untitled folder/datasets/ocn_000003.vtpd', '/Users/turuncu/Desktop/untitled folder/datasets/ocn_000004.vtpd', '/Users/turuncu/Desktop/untitled folder/datasets/ocn_000005.vtpd'])

# create a new 'Threshold'
threshold2 = Threshold(registrationName='Threshold2', Input=ocn)
threshold2.Scalars = ['CELLS', 'So_t']
threshold2.LowerThreshold = 1e+30
threshold2.UpperThreshold = 1e+30

# create a new 'Threshold'
threshold1 = Threshold(registrationName='Threshold1', Input=ocn)
threshold1.Scalars = ['CELLS', 'So_t']
threshold1.LowerThreshold = 270.0
threshold1.UpperThreshold = 310.0

# create a new 'XML Partitioned Dataset Reader'
atm = XMLPartitionedDatasetReader(registrationName='atm', FileName=['/Users/turuncu/Desktop/untitled folder/datasets/atm_000000.vtpd', '/Users/turuncu/Desktop/untitled folder/datasets/atm_000001.vtpd', '/Users/turuncu/Desktop/untitled folder/datasets/atm_000002.vtpd', '/Users/turuncu/Desktop/untitled folder/datasets/atm_000003.vtpd', '/Users/turuncu/Desktop/untitled folder/datasets/atm_000004.vtpd', '/Users/turuncu/Desktop/untitled folder/datasets/atm_000005.vtpd'])

# create a new 'Cell Data to Point Data'
cellDatatoPointData1 = CellDatatoPointData(registrationName='CellDatatoPointData1', Input=atm)
cellDatatoPointData1.CellDataArraytoprocess = ['Sa_u10m', 'Sa_v10m', 'element_mask']

# create a new 'Calculator'
calculator1 = Calculator(registrationName='Calculator1', Input=cellDatatoPointData1)
calculator1.ResultArrayName = 'e_vec'
calculator1.Function = 'norm(-sin(longitude*3.14159265/180)*iHat+cos(longitude*3.14159265/180)*jHat+0*kHat)'

# create a new 'Calculator'
calculator2 = Calculator(registrationName='Calculator2', Input=calculator1)
calculator2.ResultArrayName = 'n_vec'
calculator2.Function = 'norm((-sin(latitude*3.14159265/180)*cos(longitude*3.14159265/180))*iHat+(-sin(latitude*3.14159265/180)*sin(longitude*3.14159265/180))*jHat+cos(latitude*3.14159265/180)*kHat)'

# create a new 'Calculator'
calculator3 = Calculator(registrationName='Calculator3', Input=calculator2)
calculator3.ResultArrayName = 'vector'
calculator3.Function = 'Sa_u10m*e_vec+Sa_v10m*n_vec+0*kHat'

# create a new 'Glyph'
glyph1 = Glyph(registrationName='Glyph1', Input=calculator3,
    GlyphType='Arrow')
glyph1.OrientationArray = ['POINTS', 'vector']
glyph1.ScaleArray = ['POINTS', 'vector']
glyph1.ScaleFactor = 0.006
glyph1.GlyphTransform = 'Transform2'
glyph1.GlyphMode = 'Uniform Spatial Distribution (Surface Sampling)'
glyph1.MaximumNumberOfSamplePoints = 10000
glyph1.Stride = 16

# init the 'Transform2' selected for 'GlyphTransform'
glyph1.GlyphTransform.Scale = [1.001, 1.001, 1.001]

# create a new 'Annotate Time Filter'
annotateTimeFilter1 = AnnotateTimeFilter(registrationName='AnnotateTimeFilter1', Input=atm)
annotateTimeFilter1.Format = 'Time: {time:10.0f} s'

# ----------------------------------------------------------------
# setup the visualization in view 'renderView1'
# ----------------------------------------------------------------

# show data from threshold1
threshold1Display = Show(threshold1, renderView1, 'UnstructuredGridRepresentation')

# get 2D transfer function for 'So_t'
so_tTF2D = GetTransferFunction2D('So_t')
so_tTF2D.ScalarRangeInitialized = 1
so_tTF2D.Range = [270.0, 310.0, 0.0, 1.0]

# get color transfer function/color map for 'So_t'
so_tLUT = GetColorTransferFunction('So_t')
so_tLUT.TransferFunction2D = so_tTF2D
so_tLUT.RGBPoints = [270.0, 0.231373, 0.298039, 0.752941, 290.0, 0.865003, 0.865003, 0.865003, 310.0, 0.705882, 0.0156863, 0.14902]
so_tLUT.ScalarRangeInitialized = 1.0

# get opacity transfer function/opacity map for 'So_t'
so_tPWF = GetOpacityTransferFunction('So_t')
so_tPWF.Points = [270.0, 0.0, 0.5, 0.0, 310.0, 1.0, 0.5, 0.0]
so_tPWF.ScalarRangeInitialized = 1

# trace defaults for the display properties.
threshold1Display.Representation = 'Surface'
threshold1Display.ColorArrayName = ['CELLS', 'So_t']
threshold1Display.LookupTable = so_tLUT
threshold1Display.SelectNormalArray = 'None'
threshold1Display.SelectTangentArray = 'None'
threshold1Display.SelectTCoordArray = 'None'
threshold1Display.TextureTransform = 'Transform2'
threshold1Display.OSPRayScaleFunction = 'Piecewise Function'
threshold1Display.Assembly = 'Hierarchy'
threshold1Display.SelectedBlockSelectors = ['']
threshold1Display.SelectOrientationVectors = 'None'
threshold1Display.ScaleFactor = 0.19999904807207344
threshold1Display.SelectScaleArray = 'None'
threshold1Display.GlyphType = 'Arrow'
threshold1Display.GlyphTableIndexArray = 'None'
threshold1Display.GaussianRadius = 0.00999995240360367
threshold1Display.SetScaleArray = [None, '']
threshold1Display.ScaleTransferFunction = 'Piecewise Function'
threshold1Display.OpacityArray = [None, '']
threshold1Display.OpacityTransferFunction = 'Piecewise Function'
threshold1Display.DataAxesGrid = 'Grid Axes Representation'
threshold1Display.PolarAxes = 'Polar Axes Representation'
threshold1Display.ScalarOpacityFunction = so_tPWF
threshold1Display.ScalarOpacityUnitDistance = 0.039137106609827194
threshold1Display.OpacityArrayName = ['CELLS', 'So_t']
threshold1Display.SelectInputVectors = [None, '']
threshold1Display.WriteLog = ''

# init the 'Piecewise Function' selected for 'OSPRayScaleFunction'
threshold1Display.OSPRayScaleFunction.Points = [-49.2702, 0.0, 0.5, 0.0, 52.2462, 1.0, 0.5, 0.0]

# show data from threshold2
threshold2Display = Show(threshold2, renderView1, 'UnstructuredGridRepresentation')

# trace defaults for the display properties.
threshold2Display.Representation = 'Surface'
threshold2Display.ColorArrayName = [None, '']
threshold2Display.SelectNormalArray = 'None'
threshold2Display.SelectTangentArray = 'None'
threshold2Display.SelectTCoordArray = 'None'
threshold2Display.TextureTransform = 'Transform2'
threshold2Display.OSPRayScaleArray = 'latitude'
threshold2Display.OSPRayScaleFunction = 'Piecewise Function'
threshold2Display.Assembly = 'Hierarchy'
threshold2Display.SelectedBlockSelectors = ['']
threshold2Display.SelectOrientationVectors = 'None'
threshold2Display.ScaleFactor = 0.19940785861062113
threshold2Display.SelectScaleArray = 'None'
threshold2Display.GlyphType = 'Arrow'
threshold2Display.GlyphTableIndexArray = 'None'
threshold2Display.GaussianRadius = 0.009970392930531057
threshold2Display.SetScaleArray = ['POINTS', 'latitude']
threshold2Display.ScaleTransferFunction = 'Piecewise Function'
threshold2Display.OpacityArray = ['POINTS', 'latitude']
threshold2Display.OpacityTransferFunction = 'Piecewise Function'
threshold2Display.DataAxesGrid = 'Grid Axes Representation'
threshold2Display.PolarAxes = 'Polar Axes Representation'
threshold2Display.ScalarOpacityUnitDistance = 0.04864874875510155
threshold2Display.OpacityArrayName = ['POINTS', 'latitude']
threshold2Display.SelectInputVectors = [None, '']
threshold2Display.WriteLog = ''

# init the 'Piecewise Function' selected for 'OSPRayScaleFunction'
threshold2Display.OSPRayScaleFunction.Points = [-49.2702, 0.0, 0.5, 0.0, 52.2462, 1.0, 0.5, 0.0]

# init the 'Piecewise Function' selected for 'ScaleTransferFunction'
threshold2Display.ScaleTransferFunction.Points = [-90.125, 0.0, 0.5, 0.0, 83.625, 1.0, 0.5, 0.0]

# init the 'Piecewise Function' selected for 'OpacityTransferFunction'
threshold2Display.OpacityTransferFunction.Points = [-90.125, 0.0, 0.5, 0.0, 83.625, 1.0, 0.5, 0.0]

# show data from world_coastlines_and_lakesvtp
world_coastlines_and_lakesvtpDisplay = Show(world_coastlines_and_lakesvtp, renderView1, 'GeometryRepresentation')

# trace defaults for the display properties.
world_coastlines_and_lakesvtpDisplay.Representation = 'Surface'
world_coastlines_and_lakesvtpDisplay.AmbientColor = [0.0, 0.0, 0.0]
world_coastlines_and_lakesvtpDisplay.ColorArrayName = ['POINTS', '']
world_coastlines_and_lakesvtpDisplay.DiffuseColor = [0.0, 0.0, 0.0]
world_coastlines_and_lakesvtpDisplay.SelectNormalArray = 'None'
world_coastlines_and_lakesvtpDisplay.SelectTangentArray = 'None'
world_coastlines_and_lakesvtpDisplay.SelectTCoordArray = 'None'
world_coastlines_and_lakesvtpDisplay.TextureTransform = 'Transform2'
world_coastlines_and_lakesvtpDisplay.OSPRayScaleFunction = 'Piecewise Function'
world_coastlines_and_lakesvtpDisplay.Assembly = ''
world_coastlines_and_lakesvtpDisplay.SelectedBlockSelectors = ['']
world_coastlines_and_lakesvtpDisplay.SelectOrientationVectors = 'None'
world_coastlines_and_lakesvtpDisplay.ScaleFactor = 0.19942809939384462
world_coastlines_and_lakesvtpDisplay.SelectScaleArray = 'plates'
world_coastlines_and_lakesvtpDisplay.GlyphType = 'Arrow'
world_coastlines_and_lakesvtpDisplay.GlyphTableIndexArray = 'plates'
world_coastlines_and_lakesvtpDisplay.GaussianRadius = 0.00997140496969223
world_coastlines_and_lakesvtpDisplay.SetScaleArray = [None, '']
world_coastlines_and_lakesvtpDisplay.ScaleTransferFunction = 'Piecewise Function'
world_coastlines_and_lakesvtpDisplay.OpacityArray = [None, '']
world_coastlines_and_lakesvtpDisplay.OpacityTransferFunction = 'Piecewise Function'
world_coastlines_and_lakesvtpDisplay.DataAxesGrid = 'Grid Axes Representation'
world_coastlines_and_lakesvtpDisplay.PolarAxes = 'Polar Axes Representation'
world_coastlines_and_lakesvtpDisplay.SelectInputVectors = [None, '']
world_coastlines_and_lakesvtpDisplay.WriteLog = ''

# init the 'Piecewise Function' selected for 'OSPRayScaleFunction'
world_coastlines_and_lakesvtpDisplay.OSPRayScaleFunction.Points = [-49.2702, 0.0, 0.5, 0.0, 52.2462, 1.0, 0.5, 0.0]

# show data from glyph1
glyph1Display = Show(glyph1, renderView1, 'GeometryRepresentation')

# trace defaults for the display properties.
glyph1Display.Representation = 'Surface'
glyph1Display.AmbientColor = [0.0, 0.0, 0.0]
glyph1Display.ColorArrayName = [None, '']
glyph1Display.DiffuseColor = [0.0, 0.0, 0.0]
glyph1Display.SelectNormalArray = 'None'
glyph1Display.SelectTangentArray = 'None'
glyph1Display.SelectTCoordArray = 'None'
glyph1Display.TextureTransform = 'Transform2'
glyph1Display.OSPRayScaleArray = 'Sa_u10m'
glyph1Display.OSPRayScaleFunction = 'Piecewise Function'
glyph1Display.Assembly = 'Hierarchy'
glyph1Display.SelectedBlockSelectors = ['']
glyph1Display.SelectOrientationVectors = 'vector'
glyph1Display.ScaleFactor = 0.23513206243515017
glyph1Display.SelectScaleArray = 'None'
glyph1Display.GlyphType = 'Arrow'
glyph1Display.GlyphTableIndexArray = 'None'
glyph1Display.GaussianRadius = 0.011756603121757508
glyph1Display.SetScaleArray = ['POINTS', 'Sa_u10m']
glyph1Display.ScaleTransferFunction = 'Piecewise Function'
glyph1Display.OpacityArray = ['POINTS', 'Sa_u10m']
glyph1Display.OpacityTransferFunction = 'Piecewise Function'
glyph1Display.DataAxesGrid = 'Grid Axes Representation'
glyph1Display.PolarAxes = 'Polar Axes Representation'
glyph1Display.SelectInputVectors = ['POINTS', 'vector']
glyph1Display.WriteLog = ''

# init the 'Piecewise Function' selected for 'OSPRayScaleFunction'
glyph1Display.OSPRayScaleFunction.Points = [-49.2702, 0.0, 0.5, 0.0, 52.2462, 1.0, 0.5, 0.0]

# init the 'Piecewise Function' selected for 'ScaleTransferFunction'
glyph1Display.ScaleTransferFunction.Points = [-15.764785766601562, 0.0, 0.5, 0.0, 19.567245483398438, 1.0, 0.5, 0.0]

# init the 'Piecewise Function' selected for 'OpacityTransferFunction'
glyph1Display.OpacityTransferFunction.Points = [-15.764785766601562, 0.0, 0.5, 0.0, 19.567245483398438, 1.0, 0.5, 0.0]

# show data from annotateTimeFilter1
annotateTimeFilter1Display = Show(annotateTimeFilter1, renderView1, 'TextSourceRepresentation')

# setup the color legend parameters for each legend in this view

# get color legend/bar for so_tLUT in view renderView1
so_tLUTColorBar = GetScalarBar(so_tLUT, renderView1)
so_tLUTColorBar.Title = 'SST [K]'
so_tLUTColorBar.ComponentTitle = ''

# set color bar visibility
so_tLUTColorBar.Visibility = 1

# show color legend
threshold1Display.SetScalarBarVisibility(renderView1, True)

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
animationScene1.AnimationTime = 216000.0
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
pNG1.Writer.ImageResolution = [2044, 1456]
pNG1.Writer.Format = 'PNG'

# ----------------------------------------------------------------
# restore active source
SetActiveSource(pNG1)
# ----------------------------------------------------------------

# ------------------------------------------------------------------------------
# Catalyst options
from paraview import catalyst
options = catalyst.Options()
options.GlobalTrigger = 'Time Step'
options.CatalystLiveTrigger = 'Time Step'
options.ExtractsOutputDirectory = 'output'

# ------------------------------------------------------------------------------
if __name__ == '__main__':
    from paraview.simple import SaveExtractsUsingCatalystOptions
    # Code for non in-situ environments; if executing in post-processing
    # i.e. non-Catalyst mode, let's generate extracts using Catalyst options
    SaveExtractsUsingCatalystOptions(options)
