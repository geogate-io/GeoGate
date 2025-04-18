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
renderView1.CameraPosition = [0.0, 0.0, 3.2903743041222895]
renderView1.CameraFocalDisk = 1.0
renderView1.CameraParallelScale = 0.8516115354228021
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

# create a new 'Sphere'
sphere1 = Sphere(registrationName='Sphere1')

# ----------------------------------------------------------------
# setup the visualization in view 'renderView1'
# ----------------------------------------------------------------

# show data from sphere1
sphere1Display = Show(sphere1, renderView1, 'GeometryRepresentation')

# trace defaults for the display properties.
sphere1Display.Representation = 'Surface'
sphere1Display.AmbientColor = [0.0, 1.0, 0.0]
sphere1Display.ColorArrayName = [None, '']
sphere1Display.DiffuseColor = [0.0, 1.0, 0.0]
sphere1Display.SelectNormalArray = 'Normals'
sphere1Display.SelectTangentArray = 'None'
sphere1Display.SelectTCoordArray = 'None'
sphere1Display.TextureTransform = 'Transform2'
sphere1Display.OSPRayScaleArray = 'Normals'
sphere1Display.OSPRayScaleFunction = 'Piecewise Function'
sphere1Display.Assembly = ''
sphere1Display.SelectedBlockSelectors = ['']
sphere1Display.SelectOrientationVectors = 'None'
sphere1Display.ScaleFactor = 0.1
sphere1Display.SelectScaleArray = 'None'
sphere1Display.GlyphType = 'Arrow'
sphere1Display.GlyphTableIndexArray = 'None'
sphere1Display.GaussianRadius = 0.005
sphere1Display.SetScaleArray = ['POINTS', 'Normals']
sphere1Display.ScaleTransferFunction = 'Piecewise Function'
sphere1Display.OpacityArray = ['POINTS', 'Normals']
sphere1Display.OpacityTransferFunction = 'Piecewise Function'
sphere1Display.DataAxesGrid = 'Grid Axes Representation'
sphere1Display.PolarAxes = 'Polar Axes Representation'
sphere1Display.SelectInputVectors = ['POINTS', 'Normals']
sphere1Display.WriteLog = ''

# init the 'Piecewise Function' selected for 'OSPRayScaleFunction'
sphere1Display.OSPRayScaleFunction.Points = [-49.2702, 0.0, 0.5, 0.0, 52.2462, 1.0, 0.5, 0.0]

# init the 'Piecewise Function' selected for 'ScaleTransferFunction'
sphere1Display.ScaleTransferFunction.Points = [-0.9749279022216797, 0.0, 0.5, 0.0, 0.9749279022216797, 1.0, 0.5, 0.0]

# init the 'Piecewise Function' selected for 'OpacityTransferFunction'
sphere1Display.OpacityTransferFunction.Points = [-0.9749279022216797, 0.0, 0.5, 0.0, 0.9749279022216797, 1.0, 0.5, 0.0]

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
options.ExtractsOutputDirectory = '.'
options.GlobalTrigger = 'Time Step'
options.CatalystLiveTrigger = 'Time Step'

# ------------------------------------------------------------------------------
if __name__ == '__main__':
    from paraview.simple import SaveExtractsUsingCatalystOptions
    # Code for non in-situ environments; if executing in post-processing
    # i.e. non-Catalyst mode, let's generate extracts using Catalyst options
    SaveExtractsUsingCatalystOptions(options)
