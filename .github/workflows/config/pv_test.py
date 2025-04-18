#!/usr/bin/env pvpython

from paraview.simple import *

# Lets create a sphere
sphere=Sphere()
Show()
Render()

# get active view
renderView1 = GetActiveViewOrCreate('RenderView')
renderView1.ViewSize = [1670, 1091]

# get display properties
sphere1Display = GetDisplayProperties(sphere, view=renderView1)

# change solid color
sphere1Display.AmbientColor = [0.0, 1.0, 0.0]
sphere1Display.DiffuseColor = [0.0, 1.0, 0.0]

# save screenshot
SaveScreenshot('greenSphereScreenshot.png', renderView1,
ImageResolution=[1670, 1091])
