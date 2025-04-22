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
renderView1.ViewSize = [2044, 1304]
renderView1.AxesGrid = 'Grid Axes 3D Actor'
renderView1.CenterOfRotation = [0.00026260578632353315, 0.0016253846883774736, -0.0010860782861710216]
renderView1.StereoType = 'Crystal Eyes'
renderView1.CameraPosition = [-1.3043184166551467, -3.4950473784632896, 0.7371981955876353]
renderView1.CameraFocalPoint = [0.00026260578632353283, 0.0016253846883774743, -0.0010860782861710208]
renderView1.CameraViewUp = [0.07471848501013384, 0.17924282961569296, 0.9809633815944152]
renderView1.CameraFocalDisk = 1.0
renderView1.CameraParallelScale = 1.744385069348389
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
layout1.SetSize(2044, 1304)

# ----------------------------------------------------------------
# restore active view
SetActiveView(renderView1)
# ----------------------------------------------------------------

# ----------------------------------------------------------------
# setup the data processing pipelines
# ----------------------------------------------------------------

# create a new 'Annotate Time'
annotateTime1 = AnnotateTime(registrationName='AnnotateTime1')
annotateTime1.Format = 'Time: {time:8.1f} s'

# create a new 'XML Partitioned Dataset Reader'
ocn = XMLPartitionedDatasetReader(registrationName='ocn', FileName=['/Users/turuncu/Desktop/datasets_a/ocn_000000.vtpd', '/Users/turuncu/Desktop/datasets_a/ocn_000001.vtpd', '/Users/turuncu/Desktop/datasets_a/ocn_000002.vtpd', '/Users/turuncu/Desktop/datasets_a/ocn_000003.vtpd', '/Users/turuncu/Desktop/datasets_a/ocn_000004.vtpd', '/Users/turuncu/Desktop/datasets_a/ocn_000005.vtpd'])

# create a new 'XML Partitioned Dataset Reader'
atm = XMLPartitionedDatasetReader(registrationName='atm', FileName=['/Users/turuncu/Desktop/datasets_a/atm_000000.vtpd', '/Users/turuncu/Desktop/datasets_a/atm_000001.vtpd', '/Users/turuncu/Desktop/datasets_a/atm_000002.vtpd', '/Users/turuncu/Desktop/datasets_a/atm_000003.vtpd', '/Users/turuncu/Desktop/datasets_a/atm_000004.vtpd', '/Users/turuncu/Desktop/datasets_a/atm_000005.vtpd'])

# create a new 'Cell Data to Point Data'
cellDatatoPointData1 = CellDatatoPointData(registrationName='CellDatatoPointData1', Input=atm)
cellDatatoPointData1.CellDataArraytoprocess = ['Sa_u10m', 'Sa_v10m', 'element_mask']

# create a new 'Calculator'
calculator1 = Calculator(registrationName='Calculator1', Input=cellDatatoPointData1)
calculator1.ResultArrayName = 'e_vec'
calculator1.Function = 'norm(-sin(longitude*3.14159265/180)*iHat+cos(longitude*3.14159265/180)*jHat+0*kHat)'

# create a new 'Threshold'
threshold1 = Threshold(registrationName='Threshold1', Input=ocn)
threshold1.Scalars = ['CELLS', 'element_mask']

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
glyph1.ScaleFactor = 0.0075
glyph1.GlyphTransform = 'Transform2'
glyph1.GlyphMode = 'Uniform Spatial Distribution (Surface Sampling)'
glyph1.Stride = 16

# create a new 'XML PolyData Reader'
world_coastlines_and_lakesvtp = XMLPolyDataReader(registrationName='world_coastlines_and_lakes.vtp', FileName=['world_coastlines_and_lakes.vtp'])
world_coastlines_and_lakesvtp.CellArrayStatus = ['plates']
world_coastlines_and_lakesvtp.TimeArray = 'None'

# ----------------------------------------------------------------
# setup the visualization in view 'renderView1'
# ----------------------------------------------------------------

# show data from atm
atmDisplay = Show(atm, renderView1, 'UnstructuredGridRepresentation')

# trace defaults for the display properties.
atmDisplay.Representation = 'Surface'
atmDisplay.ColorArrayName = [None, '']
atmDisplay.SelectNormalArray = 'None'
atmDisplay.SelectTangentArray = 'None'
atmDisplay.SelectTCoordArray = 'None'
atmDisplay.TextureTransform = 'Transform2'
atmDisplay.Scale = [0.998, 0.998, 0.998]
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

# init the 'Polar Axes Representation' selected for 'PolarAxes'
atmDisplay.PolarAxes.Scale = [0.998, 0.998, 0.998]

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
glyph1Display.Scale = [1.002, 1.002, 1.002]
glyph1Display.OSPRayScaleArray = 'Sa_u10m'
glyph1Display.OSPRayScaleFunction = 'Piecewise Function'
glyph1Display.Assembly = 'Hierarchy'
glyph1Display.SelectedBlockSelectors = ['']
glyph1Display.SelectOrientationVectors = 'vector'
glyph1Display.ScaleFactor = 0.20010867118835451
glyph1Display.SelectScaleArray = 'None'
glyph1Display.GlyphType = 'Arrow'
glyph1Display.GlyphTableIndexArray = 'None'
glyph1Display.GaussianRadius = 0.010005433559417725
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

# init the 'Polar Axes Representation' selected for 'PolarAxes'
glyph1Display.PolarAxes.Scale = [1.002, 1.002, 1.002]

# show data from threshold1
threshold1Display = Show(threshold1, renderView1, 'UnstructuredGridRepresentation')

# get 2D transfer function for 'So_t'
so_tTF2D = GetTransferFunction2D('So_t')
so_tTF2D.ScalarRangeInitialized = 1
so_tTF2D.Range = [270.0, 307.0, 0.0, 1.0]

# get color transfer function/color map for 'So_t'
so_tLUT = GetColorTransferFunction('So_t')
so_tLUT.TransferFunction2D = so_tTF2D
so_tLUT.RGBPoints = [270.0, 0.0862745098039216, 0.00392156862745098, 0.298039215686275, 271.1559294577548, 0.113725, 0.0235294, 0.45098, 272.1159363005615, 0.105882, 0.0509804, 0.509804, 272.7820648161063, 0.0392157, 0.0392157, 0.560784, 273.42860203724774, 0.0313725, 0.0980392, 0.6, 274.0555457361832, 0.0431373, 0.164706, 0.639216, 274.9567764679771, 0.054902, 0.243137, 0.678431, 276.1518899826376, 0.054902, 0.317647, 0.709804, 277.6212887573242, 0.0509804, 0.396078, 0.741176, 278.5739498519897, 0.0392157, 0.466667, 0.768627, 279.52661094665524, 0.0313725, 0.537255, 0.788235, 280.52090680858504, 0.0313725, 0.615686, 0.811765, 281.5396897624045, 0.0235294, 0.709804, 0.831373, 282.5584749440266, 0.0509804, 0.8, 0.85098, 283.4009295648076, 0.0705882, 0.854902, 0.870588, 284.18461030237813, 0.262745, 0.901961, 0.862745, 284.8703301123264, 0.423529, 0.941176, 0.87451, 285.9282978827555, 0.572549, 0.964706, 0.835294, 286.6336112149097, 0.658824, 0.980392, 0.843137, 287.14300269181945, 0.764706, 0.980392, 0.866667, 287.6915778714374, 0.827451, 0.980392, 0.886275, 288.7691380501711, 0.913725, 0.988235, 0.937255, 289.1022023079435, 1.0, 1.0, 0.972549019607843, 289.435266565716, 0.988235, 0.980392, 0.870588, 289.92506674822215, 0.992156862745098, 0.972549019607843, 0.803921568627451, 290.29731470870286, 0.992157, 0.964706, 0.713725, 290.9242584076384, 0.988235, 0.956863, 0.643137, 291.9234500670544, 0.980392, 0.917647, 0.509804, 292.7659069156379, 0.968627, 0.87451, 0.407843, 293.6279550586248, 0.94902, 0.823529, 0.321569, 294.2548987575602, 0.929412, 0.776471, 0.278431, 295.17572301156, 0.909804, 0.717647, 0.235294, 295.9985863379375, 0.890196, 0.658824, 0.196078, 296.6745106506347, 0.878431, 0.619608, 0.168627, 297.62717174530025, 0.870588, 0.54902, 0.156863, 298.5798328399658, 0.85098, 0.47451, 0.145098, 299.5324939346313, 0.831373, 0.411765, 0.133333, 300.48515502929683, 0.811765, 0.345098, 0.113725, 301.43781612396236, 0.788235, 0.266667, 0.0941176, 302.3904772186279, 0.741176, 0.184314, 0.0745098, 303.3431383132934, 0.690196, 0.12549, 0.0627451, 304.29579940795895, 0.619608, 0.0627451, 0.0431373, 305.1872355645857, 0.54902, 0.027451, 0.0705882, 305.97091564077743, 0.470588, 0.0156863, 0.0901961, 306.8525556699279, 0.4, 0.00392157, 0.101961, 308.10644378662107, 0.188235294117647, 0.0, 0.0705882352941176]
so_tLUT.ColorSpace = 'Lab'
so_tLUT.ScalarRangeInitialized = 1.0

# get opacity transfer function/opacity map for 'So_t'
so_tPWF = GetOpacityTransferFunction('So_t')
so_tPWF.Points = [270.0, 0.0, 0.5, 0.0, 308.10644378662107, 1.0, 0.5, 0.0]
so_tPWF.ScalarRangeInitialized = 1

# trace defaults for the display properties.
threshold1Display.Representation = 'Surface'
threshold1Display.ColorArrayName = ['CELLS', 'So_t']
threshold1Display.LookupTable = so_tLUT
threshold1Display.SelectNormalArray = 'None'
threshold1Display.SelectTangentArray = 'None'
threshold1Display.SelectTCoordArray = 'None'
threshold1Display.TextureTransform = 'Transform2'
threshold1Display.OSPRayScaleArray = 'latitude'
threshold1Display.OSPRayScaleFunction = 'Piecewise Function'
threshold1Display.Assembly = 'Hierarchy'
threshold1Display.SelectedBlockSelectors = ['']
threshold1Display.SelectOrientationVectors = 'None'
threshold1Display.ScaleFactor = 0.1999995240354704
threshold1Display.SelectScaleArray = 'None'
threshold1Display.GlyphType = 'Arrow'
threshold1Display.GlyphTableIndexArray = 'None'
threshold1Display.GaussianRadius = 0.009999976201773519
threshold1Display.SetScaleArray = ['POINTS', 'latitude']
threshold1Display.ScaleTransferFunction = 'Piecewise Function'
threshold1Display.OpacityArray = ['POINTS', 'latitude']
threshold1Display.OpacityTransferFunction = 'Piecewise Function'
threshold1Display.DataAxesGrid = 'Grid Axes Representation'
threshold1Display.PolarAxes = 'Polar Axes Representation'
threshold1Display.ScalarOpacityFunction = so_tPWF
threshold1Display.ScalarOpacityUnitDistance = 0.03421025527233762
threshold1Display.OpacityArrayName = ['POINTS', 'latitude']
threshold1Display.SelectInputVectors = [None, '']
threshold1Display.WriteLog = ''

# init the 'Piecewise Function' selected for 'OSPRayScaleFunction'
threshold1Display.OSPRayScaleFunction.Points = [-49.2702, 0.0, 0.5, 0.0, 52.2462, 1.0, 0.5, 0.0]

# init the 'Piecewise Function' selected for 'ScaleTransferFunction'
threshold1Display.ScaleTransferFunction.Points = [-90.125, 0.0, 0.5, 0.0, 90.125, 1.0, 0.5, 0.0]

# init the 'Piecewise Function' selected for 'OpacityTransferFunction'
threshold1Display.OpacityTransferFunction.Points = [-90.125, 0.0, 0.5, 0.0, 90.125, 1.0, 0.5, 0.0]

# show data from world_coastlines_and_lakesvtp
world_coastlines_and_lakesvtpDisplay = Show(world_coastlines_and_lakesvtp, renderView1, 'GeometryRepresentation')

# trace defaults for the display properties.
world_coastlines_and_lakesvtpDisplay.Representation = 'Surface'
world_coastlines_and_lakesvtpDisplay.AmbientColor = [0.0, 0.0, 0.0]
world_coastlines_and_lakesvtpDisplay.ColorArrayName = ['POINTS', '']
world_coastlines_and_lakesvtpDisplay.DiffuseColor = [0.0, 0.0, 0.0]
world_coastlines_and_lakesvtpDisplay.LineWidth = 1.5
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

# show data from annotateTime1
annotateTime1Display = Show(annotateTime1, renderView1, 'TextSourceRepresentation')

# setup the color legend parameters for each legend in this view

# get color legend/bar for so_tLUT in view renderView1
so_tLUTColorBar = GetScalarBar(so_tLUT, renderView1)
so_tLUTColorBar.Title = 'SST (K)'
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
animationScene1.AnimationTime = 129600.0
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
pNG1.Writer.ImageResolution = [2044, 1304]
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
