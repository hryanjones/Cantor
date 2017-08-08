Framer.Device.deviceType = "fullscreen"
# Everything was designed for @2x displays (which... Framer claims has have a contentScale of 1.0), so if Framer is running for a desktop display, we'll need to scale.
contentScale = if Framer.Device.deviceType == "fullscreen" then 0.5 else 1.0
Screen.backgroundColor = "white"
Framer.Extras.Hints.disable()

kaColors = require "kaColors"
utils = require "utils.coffee"
{TextLayer} = require "TextLayer.coffee"
RecorderUtility = require "recorder"
deepEqual = require "deep-equal"
# {deepEqual} = require "npm"

dashImage = require "cantor-images/dash.png"
gridImage = require "cantor-images/grid.svg"
triangleImage = require "cantor-images/triangle@2x.png"
antsImage = require "cantor-images/ants.gif"

# Configuration, constants

enableAdditionExpressionForming = false
shouldReflowSecondAdditionArgument = true

enableBackgroundGrid = true
enableBlockGrid = true
enableBlockGridTicks = false
enableBlockDigitLabels = true
enableDistinctColoringForOnesBlocks = true

enableHighContrastGrid = false

debugShowLensFrames = false

# Canvas

rootLayer = new Layer
	backgroundColor: ""
	width: Screen.width / contentScale
	height: Screen.height / contentScale
	originX: 0
	originY: 0
	scale: contentScale
document.body.addEventListener 'contextmenu', (event) ->
	event.preventDefault()

selection = null
canvasComponent = new ScrollComponent
	backgroundColor: ""
	parent: rootLayer
	width: rootLayer.width
	height: rootLayer.height
canvasComponent.style["overflow"] = "visible"
canvas = canvasComponent.content
window.rootLayer = canvasComponent
canvas.style["overflow"] = "visible"
canvas.nextPersistentID = 1 # TODO: Make a real canvas data structure...
canvas.onTap (event, layer) ->
	selection?.setSelected(false) if not layer.draggable.isDragging
canvasComponent.content.pinchable.enabled = false
canvasComponent.content.pinchable.minScale = 0.5
canvasComponent.content.pinchable.maxScale = 2
canvasComponent.content.pinchable.rotate = false
canvasComponent.content.draggable.enabled = false

if enableBackgroundGrid
	grid = new Layer
		parent: canvas
		width: 10000
		height: 10000
	grid.style["background"] = "url(#{gridImage})"
	grid.skipRecording = true
	canvasComponent.updateContent()
	grid.x -= 3600
	grid.y -= 3600

# Lenses

class Lens extends Layer
	constructor: (args) ->
		super args
		this.backgroundColor = ""
		this.value = args.value
		this.persistentID = args.persistentID
		if !this.persistentID
			# Recordings' persistent IDs should be in a different "namespace" than users'.
			this.persistentID = canvas.nextPersistentID * (if recorder.isRecording then -1 else 1)
			canvas.nextPersistentID += 1
		if debugShowLensFrames
			this.borderColor = "red"
			this.borderWidth = 1

class BlockLens extends Lens
	this.blockSize = 40
	this.interiorBorderColor = if enableBlockGrid then "rgba(85, 209, 229, 0.4)" else ""
	this.interiorBorderWidth = if enableBlockGrid then 1 else 0

	constructor: (args) ->
		super args

		this.layout = if args.layout
			Object.assign({}, args.layout)
		else
			numberOfColumns: 10
			firstRowSkip: 0
			state: "static"

		this.blockLayers = []
		for blockNumber in [0...this.value]
			block = new Layer
				parent: this
				width: BlockLens.blockSize
				height: BlockLens.blockSize
				borderColor: BlockLens.interiorBorderColor
				borderWidth: if enableBlockGrid then 1 else 0
			this.blockLayers.push block

		if enableBlockGridTicks
			this.onesTick = new Layer
				parent: this
				backgroundColor: kaColors.white
				x: BlockLens.blockSize * 5 - 1
				y: 0
				width: 2
				height: BlockLens.blockSize

			this.tensTicks = []
			for tensTickIndex in [0...Math.floor(this.value / 20)]
				tensTick = new Layer
					parent: this
					backgroundColor: kaColors.white
					x: 0
					y: BlockLens.blockSize * (tensTickIndex + 1) * 2
					width: BlockLens.blockSize * 10
					height: 2
				this.tensTicks.push(tensTick)

		this.style["-webkit-border-image"] = "url(#{antsImage}) 1 repeat repeat"

		this.wedge = new Wedge { parent: this }

		this.resizeHandle = new ResizeHandle {parent: this}

		this.reflowHandle = new ReflowHandle {parent: this}
		this.reflowHandle.midY = BlockLens.blockSize / 2 + 2
		this.reflowHandle.maxX = 0

		this.draggable.enabled = true
		this.draggable.momentum = false
		this.draggable.propagateEvents = false

		this.draggable.on Events.DragEnd, (event) =>
			this.animate
				properties:
					x: Math.round(this.x / BlockLens.blockSize) * BlockLens.blockSize
					y: Math.round(this.y / BlockLens.blockSize) * BlockLens.blockSize
				time: 0.2

		# Hello greetings. You will notice that these TouchStart and TouchEnd methods have some hit testing garbage in them. That's because Framer can't deal with event cancellation correctly for this highlight behavior vs. children's gestures (i.e. the reflow handle and wedge). This is sad. Maybe someday we'll make Framer better.
		this.on Events.TouchStart, (event, layer) ->
			this.bringToFront()
			point = Canvas.convertPointToLayer({x: event.pageX, y: event.pageY}, this.parent)
			return unless utils.pointInsideLayer(this, point)
			this.setBeingTouched(true) unless event.shiftKey

		this.on Events.TouchEnd, (event, layer) ->
			this.setBeingTouched(false)

		this.onTap (event, layer) =>
			event.stopPropagation()
			if event.shiftKey
				this.flash()
			else
				this.setSelected(true) unless this.draggable.isDragging

		if enableBlockDigitLabels
			this.digitLabel = new TextLayer
				x: -72
				fontFamily: "Helvetica"
				text: this.value
				parent: this
				color: kaColors.math1
				fontSize: 34
				autoSize: true
				backgroundColor: "rgba(255, 255, 255, 1.0)"
				borderRadius: 5
				textAlign: "right"
				paddingTop: 5
				paddingRight: 6
				borderColor: "rgba(0, 0, 0, 0.1)"
				borderWidth: 1
			this.digitLabel.width += 12
			this.digitLabel.height += 5
			this.digitLabel.index = -1

		this.update()
		this.resizeHandle.updatePosition false
		this.layoutReflowHandle false
		this.setSelected(false)

	getState: ->
		value: this.value
		layout: Object.assign {}, this.layout
		isSelected: selection == this

	applyState: (newState) ->
		this.value = newState.value
		Object.assign this.layout, newState.layout

		if selection != this and newState.isSelected
			this.setSelected true
		else if selection == this and not newState.isSelected
			this.setSelected false

		this.update false

	flash: ->
		spread = 25
		setShadow = =>
			spread -= 1
			if spread <= 0
				this.style["-webkit-filter"] = null
			else
				this.style["-webkit-filter"] = "drop-shadow(0px 0px #{spread}px #{kaColors.math1})"
				requestAnimationFrame setShadow
		setShadow()

	update: (animated) ->
		for blockNumber in [0...this.value]
			blockLayer = this.blockLayers[blockNumber]
			indexForLayout = blockNumber + this.layout.firstRowSkip
			columnNumber = indexForLayout % this.layout.numberOfColumns
			newX = BlockLens.blockSize * columnNumber
			rowNumber = Math.floor(indexForLayout / this.layout.numberOfColumns)
			newY = BlockLens.blockSize * rowNumber
			if (this.layout.rowSplitIndex != null) and (rowNumber >= this.layout.rowSplitIndex)
				newY += Wedge.splitY
			if animated
				blockLayer.animate {properties: {x: newX, y: newY}, time: 0.15}
			else
				blockLayer.props = {x: newX, y: newY}

			# Update the borders:
			heavyStrokeColor = kaColors.white
			setBorder = (side, heavy) ->
				blockLayer.style["border-#{side}-color"] = if heavy then heavyStrokeColor else BlockLens.interiorBorderColor
				blockLayer.style["border-#{side}-width"] = if heavy then "2px" else "#{BlockLens.interiorBorderWidth}px"

			lastRow = Math.ceil((this.value + this.layout.firstRowSkip) / this.layout.numberOfColumns)
			lastRowExtra = (this.value + this.layout.firstRowSkip) - (lastRow - 1) * this.layout.numberOfColumns
			setBorder "left", columnNumber == 0 or blockNumber == 0
			setBorder "top", rowNumber == 0 or (rowNumber == 1 and columnNumber < this.layout.firstRowSkip)
			setBorder "bottom", rowNumber == (lastRow - 1) or (rowNumber == (lastRow - 2) and columnNumber >= lastRowExtra)
			setBorder "right", columnNumber == this.layout.numberOfColumns - 1 or (rowNumber == (lastRow - 1) and columnNumber == (lastRowExtra - 1))

			blockLayer.backgroundColor = if this.isBeingTouched then kaColors.math3 else kaColors.math1
			if enableDistinctColoringForOnesBlocks and ((rowNumber == (lastRow - 1) and lastRowExtra < this.layout.numberOfColumns) or (rowNumber == 0 and this.layout.firstRowSkip > 0))
				blockLayer.backgroundColor = if this.isBeingTouched then kaColors.science3 else kaColors.science1

		# Resize lens to fit blocks.
		contentFrame = this.contentFrame()
		this.width = BlockLens.blockSize * this.layout.numberOfColumns + 2
		this.height = this.blockLayers[this.value - 1].maxY + 2

		# Update the grid ticks:
		if enableBlockGridTicks
			this.onesTick.height = Math.floor((this.value + this.layout.firstRowSkip) / this.layout.numberOfColumns) * BlockLens.blockSize
			# If the first row starts after 5, hide the ones tick.
			if this.layout.firstRowSkip >= 5
				this.onesTick.y = BlockLens.blockSize
				this.onesTick.height -= BlockLens.blockSize
			else
				this.onesTick.y = 0
			# If the last row doesn't reach the 5s place, make it a bit shorter.
			lastRowLength = (this.value + this.layout.firstRowSkip) % this.layout.numberOfColumns
			this.onesTick.height += BlockLens.blockSize if lastRowLength >= 5
			this.onesTick.visible = Math.min(this.value, this.layout.numberOfColumns) >= 5
			tensTick.width = (BlockLens.blockSize * this.layout.numberOfColumns) for tensTick in this.tensTicks

		if enableBlockDigitLabels
			this.digitLabel.midY = this.height - 20

		this.resizeHandle.visible = (selection == this) and (this.layout.state != "tentativeReceiving")
		this.resizeHandle.updateSublayers()

		if not this.wedge.draggable.isDragging
			this.wedge.x = this.width + Wedge.restingX

	layoutReflowHandle: (animated) ->
# 		this.reflowHandle.animate
# 			properties:
# 				x: Math.max(-BlockLens.resizeHandleSize / 2, this.reflowHandle.x)
# 				y: (BlockLens.blockSize - BlockLens.resizeHandleSize) / 2
# 			time: if animated then 0.1 else 0

	setSelected: (isSelected) ->
		selectionBorderWidth = 1
		selection?.setSelected(false) if selection != this
		this.borderWidth = if isSelected then selectionBorderWidth else 0
		this.resizeHandle.visible = isSelected
		this.reflowHandle.visible = isSelected
		this.wedge.visible = isSelected

		if (isSelected and selection != this) or (not isSelected and selection == this)
			this.x += if isSelected then -selectionBorderWidth else selectionBorderWidth
			this.y += if isSelected then -selectionBorderWidth else selectionBorderWidth

		selection = if isSelected then this else null

	#gets called on touch down and touch up events
	setBeingTouched: (isBeingTouched) ->
		this.isBeingTouched = isBeingTouched
		this.update()

	splitAt: (rowSplitIndex) ->
		newValueA = Math.min(rowSplitIndex * this.layout.numberOfColumns - this.layout.firstRowSkip, this.value)
		newValueB = this.value - newValueA

		this.layout.rowSplitIndex = null

		newBlockA = new BlockLens
			value: newValueA
			parent: this.parent
			x: this.x
			y: this.y
			layout: this.layout

		this.layout.firstRowSkip = 0
		newBlockB = new BlockLens
			value: newValueB
			parent: this.parent
			x: this.x
			y: newBlockA.maxY + Wedge.splitY
			layout: this.layout

		this.destroy()


class ReflowHandle extends Layer
	this.knobSize = 30
	this.knobRightMargin = 45

	constructor: (args) ->
		throw "Requires parent layer" if args.parent == null

		super args
		this.props =
			backgroundColor: ""
			width: 110
			height: 110

		verticalBrace = new Layer
			parent: this
			width: 5
			height: BlockLens.blockSize
			maxX: this.maxX
			midY: this.midY
			backgroundColor: kaColors.math2

		horizontalBrace = new Layer
			parent: this
			width: ReflowHandle.knobRightMargin + ReflowHandle.knobSize / 2
			height: 2
			maxX: verticalBrace.x
			midY: this.midY
			backgroundColor: kaColors.math2

		knob = new Layer
			parent: this
			backgroundColor: kaColors.math2
			width: ReflowHandle.knobSize
			height: ReflowHandle.knobSize
			midX: horizontalBrace.x
			midY: this.midY
			borderRadius: ReflowHandle.knobSize / 2


		verticalKnobTrack = new Layer
			parent: this
			width: 2
			midX: knob.midX
			opacity: 0
		verticalKnobTrack.sendToBack()

		updateVerticalKnobTrackGradient = =>
			fadeLength = 75
			trackLengthBeyondKnob = 200
			trackColor = kaColors.math2
			transparentTrackColor = "rgba(85, 209, 229, 0.0)"

			bottomFadeStartingHeight = trackLengthBeyondKnob + Math.abs(knob.midY) + trackLengthBeyondKnob - fadeLength
			verticalKnobTrack.height = trackLengthBeyondKnob + Math.abs(knob.midY) + trackLengthBeyondKnob
			verticalKnobTrack.y = -trackLengthBeyondKnob + this.midY + Math.min(0, knob.midY)
			verticalKnobTrack.style["-webkit-mask-image"] = "url(#{dashImage})"
			verticalKnobTrack.style.background = "-webkit-linear-gradient(top, #{transparentTrackColor} 0%, #{trackColor} #{fadeLength}px, #{trackColor} #{bottomFadeStartingHeight}px, #{transparentTrackColor} 100%)"

		updateVerticalKnobTrackGradient()

		this.onTouchStart ->
			knob.animate { properties: {scale: 2}, time: 0.2 }
			verticalKnobTrack.animate { properties: {opacity: 1}, time: 0.2}

		this.onTouchEnd ->
			knob.animate { properties: {scale: 1}, time: 0.2 }
			verticalKnobTrack.animate { properties: {opacity: 0}, time: 0.2}

		this.onPan (event) ->
			knob.y += event.delta.y / contentScale
			this.x += event.delta.x / contentScale
			updateVerticalKnobTrackGradient()

			this.parent.layout.firstRowSkip = utils.clip(Math.ceil(this.maxX / BlockLens.blockSize), 0, this.parent.layout.numberOfColumns - 1)
			this.parent.update()

			event.stopPropagation()

		this.onPanEnd =>
			isAnimating = true
			knobAnimation = knob.animate { properties: {midY: this.height / 2}, time: 0.2 }
			knobAnimation.on Events.AnimationEnd, ->
				isAnimating = false

			updateVerticalTrackForAnimation = ->
				return unless isAnimating
				updateVerticalKnobTrackGradient()
				requestAnimationFrame updateVerticalTrackForAnimation
			requestAnimationFrame updateVerticalTrackForAnimation

			this.animate { properties: { maxX: BlockLens.blockSize * this.parent.layout.firstRowSkip }, time: 0.2}

			event.stopPropagation()

class ResizeHandle extends Layer
	this.knobSize = 30
	# This is kinda complicated... because we don't want touches on the resize handle to conflict with touches on the blocks themselves, we make it easier to "miss" the resize handle down and to the right of its actual position than up or to the left.
	this.knobHitTestBias = 10

	constructor: (args) ->
		throw "Requires parent layer" if args.parent == null

		super args
		this.props =
			backgroundColor: ""
			width: 88

		knob = new Layer
			parent: this
			backgroundColor: ""
			midX: this.midX + ResizeHandle.knobHitTestBias
			width: this.width
			height: this.width
		this.knob = knob

		knobDot = new Layer
			parent: knob
			backgroundColor: kaColors.math2
			midX: knob.width / 2 - ResizeHandle.knobHitTestBias
			midY: knob.midY -  ResizeHandle.knobHitTestBias
			width: ResizeHandle.knobSize
			height: ResizeHandle.knobSize
			borderRadius: ResizeHandle.knobSize / 2

		this.verticalBrace = new Layer
			parent: this
			width: 5
			midX: this.midX
			backgroundColor: kaColors.math2

		verticalKnobTrack = new Layer
			parent: this
			width: 2
			midX: this.midX
			opacity: 0
		verticalKnobTrack.sendToBack()

		this.updateVerticalKnobTrackGradient = =>
			fadeLength = 150
			trackLengthBeyondKnob = 250
			trackColor = kaColors.math2
			transparentTrackColor = "rgba(85, 209, 229, 0.0)"

			bottomFadeStartingHeight = knob.midY - this.verticalBrace.maxY
			verticalKnobTrack.height = knob.midY - this.verticalBrace.maxY + trackLengthBeyondKnob
			verticalKnobTrack.y = this.verticalBrace.maxY
			verticalKnobTrack.style["-webkit-mask-image"] = "url(#{dashImage})"
			verticalKnobTrack.style["mask-image"] = "url(#{dashImage})"
			verticalKnobTrack.style.background = "-webkit-linear-gradient(top, #{trackColor} 0%, #{trackColor} #{bottomFadeStartingHeight}px, #{transparentTrackColor} 100%)"

		this.updateVerticalKnobTrackGradient()

		this.knob.onTouchStart =>
			knobDot.animate { properties: { scale: 2 }, time: 0.2 }
			verticalKnobTrack.animate { properties: { opacity: 1 }, time: 0.2}

			# This is pretty hacky, even for a prototype. Eh.
			this.parent.wedge.animate { properties: { opacity: 0 }, time: 0.2 }

		this.knob.onTouchEnd =>
			knobDot.animate { properties: { scale: 1 }, time: 0.2 }
			verticalKnobTrack.animate { properties: { opacity: 0 }, time: 0.2}
			this.parent.wedge.animate { properties: { opacity: 1 }, time: 0.4, delay: 0.4 }

		this.knob.onPan (event) =>
			knob.y += event.delta.y / contentScale
			this.x += event.delta.x / contentScale
			this.updateVerticalKnobTrackGradient()

			this.parent.layout.numberOfColumns = Math.max(1, Math.floor((this.x + this.verticalBrace.x) / BlockLens.blockSize))
			this.parent.update()

			event.stopPropagation()

		this.knob.onPanEnd =>
			this.updatePosition true
			event.stopPropagation()

	updateSublayers: ->
		this.verticalBrace.y = 0
		this.verticalBrace.height = this.parent.height - this.y
		this.height = this.knob.maxY

	updatePosition: (animated) ->
		this.y = 2
		this.animate
			properties: { midX: BlockLens.blockSize * this.parent.layout.numberOfColumns + 2 }
			time: if animated then 0.2 else 0

		isAnimating = true
		knobAnimation = this.knob.animate
			properties: { midY: this.parent.height - this.y + ResizeHandle.knobHitTestBias }
			time: if animated then 0.2 else 0
		knobAnimation.on Events.AnimationEnd, ->
			isAnimating = false

		updateVerticalTrackForAnimation = =>
			this.updateSublayers()
			return unless isAnimating
			this.updateVerticalKnobTrackGradient()
			requestAnimationFrame updateVerticalTrackForAnimation
		requestAnimationFrame updateVerticalTrackForAnimation

class Wedge extends Layer
	this.restingX = 30
	this.splitY = BlockLens.blockSize

	constructor: (args) ->
		throw "Requires parent layer" if args.parent == null
		super args
		this.props =
			image: triangleImage
			width: 80
			height: 40
			backgroundColor: ""
			x: Wedge.restingX
			scaleX: -1

		this.draggable.enabled = true
		this.draggable.momentum = false
		this.draggable.propagateEvents = false

		this.draggable.on Events.DragMove, (event) =>
			this.parent.layout.rowSplitIndex = if this.minX <= this.parent.width
				Math.round(this.midY / BlockLens.blockSize)
			else
				null
			this.parent.update(true)

		this.draggable.on Events.DragEnd, (event) =>
			if (this.minX <= this.parent.width) and (this.parent.layout.rowSplitIndex > 0) and (this.parent.layout.rowSplitIndex <= Math.floor(this.parent.value / this.parent.layout.numberOfColumns))
				this.parent.splitAt(this.parent.layout.rowSplitIndex)
			else
				this.animate
					properties: { x: this.parent.width + Wedge.restingX, y: 0 }
					time: 0.2

		this.onTap (event) -> event.stopPropagation()

# Controls

class GlobalButton extends Layer
	constructor: (args) ->
		super args
		props =
			backgroundColor: kaColors.white
			borderColor: kaColors.gray76
			borderRadius: 8
			borderWidth: 1
			width: 100
			height: 100
		this.style["cursor"] = "pointer"
		Object.assign(props, args)
		this.props = props
		this.action = args.action

		originalBackgroundColor = this.backgroundColor
		this.onTouchStart ->
			this.backgroundColor = kaColors.gray95
		# TODO implement proper button hit-testing-on-move behavior
		this.onTouchEnd ->
			this.backgroundColor = originalBackgroundColor
			this.action?()

addBlockPromptLabel = new Layer
	parent: rootLayer
	width: rootLayer.width
	backgroundColor: kaColors.cs1
	height: 88
	y: -88
	index: 500
addBlockPromptLabelText = new TextLayer
	parent: addBlockPromptLabel
	text: "Touch and drag to add a value"
	textAlign: "center"
	fontSize: 40
	color: kaColors.white
	autoSize: true
	y: Align.center()
	width: addBlockPromptLabel.width

state = 0
nextButton = new GlobalButton
	opacity: 0
	parent: rootLayer
	x: Align.right(-160)
	y: Align.bottom(-20)
	visible: false
	action: ->
		state = state + 1
		recorder.playSavedRecording state
nextButton.html = "<div style='color: #{kaColors.math1}; font-size: 60px; text-align: center; margin: 35% 0%'>➡️</div>"

addButton = new GlobalButton
	parent: rootLayer
	x: Align.right(-20)
	y: Align.bottom(-20)
	opacity: 0
	action: ->
		setIsAdding(not isAdding)

addCrosshair = new Layer
	backgroundColor: "clear"
	parent: rootLayer
	width: 0
	height: 0
addCrosshair.html = "<div style='color: #{kaColors.math1}; font-size: 60px; text-align: center; margin: -17px -17px'>+</div>"
window.addEventListener "mousemove", (event) ->
	addCrosshair.x = event.clientX / contentScale
	addCrosshair.y = event.clientY / contentScale

isAdding = null
setIsAdding = (newIsAdding) ->
	return if newIsAdding == isAdding
	isAdding = newIsAdding
	if isAdding
		canvasComponent.scroll = false
	else
		canvasComponent.scroll = true
	addCrosshair.visible = newIsAdding
# 	addBlockPromptLabel.animate
# 		properties: {y: if isAdding then 0 else -addBlockPromptLabel.height}
# 		time: 0.2
# 	addButton.html = "<div style='color: #{kaColors.math1}; font-size: 70px; text-align: center; margin: 25% 0%'>#{if isAdding then 'x' else '+'}</div>"

setIsAdding(false)

pendingBlockToAdd = null
pendingBlockToAddLabel = new TextLayer
	fontFamily: "Helvetica"
	parent: canvas
	color: kaColors.math1
	fontSize: 72
	autoSize: true
	backgroundColor: "rgba(255, 255, 255, 0.9)"
	borderRadius: 4
	textAlign: "center"
	paddingTop: 10
	paddingLeft: 10
	paddingRight: 10
	paddingBottom: 10
	borderRadius: 4
	text: ""

canvas.onPanStart ->
	return unless isAdding

	pendingBlockToAddLabel.bringToFront()

canvas.onPan (event) ->
	return unless isAdding

	value = 10 * Math.max(0, Math.floor((event.point.y - event.start.y) / contentScale / BlockLens.blockSize)) + utils.clip(Math.floor((event.point.x - event.start.x) / contentScale / BlockLens.blockSize) + 1, 0, 10)
	value = Math.max(1, value)
	return if value == pendingBlockToAdd?.value

	startingLocation = Screen.convertPointToLayer(event.start, canvas)
	startingLocation.x = Math.floor(startingLocation.x / BlockLens.blockSize) * BlockLens.blockSize
	startingLocation.y = Math.floor(startingLocation.y / BlockLens.blockSize) * BlockLens.blockSize 
	pendingBlockToAdd?.destroy()
	pendingBlockToAdd = new BlockLens
		parent: canvas
		x: startingLocation.x
		y: startingLocation.y
		value: value
	pendingBlockToAdd.borderWidth = 1

	pendingBlockToAddLabel.visible = true
	pendingBlockToAddLabel.text = pendingBlockToAdd.value
	pendingBlockToAddLabel.midX = startingLocation.x + BlockLens.blockSize * 5
	pendingBlockToAddLabel.y = startingLocation.y - 100

canvas.onPanEnd ->
	return unless isAdding
	pendingBlockToAdd?.borderWidth = 0
	pendingBlockToAdd = null

	pendingBlockToAddLabel.visible = false
	setIsAdding false

# Recording and playback

class Recorder
	baseRecordingTime: null
	recordedEvents: []
	isPlayingBackRecording: false
	isRecording: false
	shouldLoop: true

	constructor: (relevantLayerGetter) ->
		window.AudioContext = window.AudioContext || window.webkitAudioContext
		navigator.getUserMedia = navigator.getUserMedia || navigator.webkitGetUserMedia
		this.audioContext = new AudioContext

		window.addEventListener("keydown", (event) =>
			if event.keyCode == 17
				setIsAdding true

			key = String.fromCharCode(event.keyCode)
			if key == "C"
				this.clear()
			if key == "P"
				this.startPlaying()
			if key == "R"
				if this.isRecording
					this.stopRecording()
				else
					this.startRecording()
			if key == "D"
				this.downloadRecording()
			if key == "S"
				this.startRecording(true)
				this.stopRecording()
				this.downloadRecording()				
			if key == "O"
				input = document.createElement "input"
				input.type = "file"
				document.body.appendChild input
				input.addEventListener 'change', (event) =>
					reader = new FileReader()
					reader.onload = (fileEvent) =>
						console.log(reader.result)
						for layer in this.relevantLayerGetter()
							layer.destroy() if layer.persistentID
						this.playRecordedData reader.result
						this.stopPlaying()
					reader.readAsText(input.files[0])
				input.click()

		)
		
		window.addEventListener("keyup", (event) =>
			if event.keyCode == 17
				setIsAdding false
		)
		this.relevantLayerGetter = relevantLayerGetter

		this.ignoredPersistentIDs = new Set()
		this.highestIDToTouchInRecordings = 0

	playRecordedData: (data) =>
		this.lastPlayedRecordedData = data
		# We do an awkward little pass here as we read in the JSON to make sure all the persistent IDs are negative. We associate negative IDs with recordings and treat them separately from users' blocks. We never want to delete a user's blocks, for instance.
		events = JSON.parse(data, (key, value) ->
			if key == "persistentIDs"
				negativeIDs = value.map (id) -> Math.abs(parseInt(id)) * -1
				return new Set(negativeIDs)
			else
				return value
		)
		this.recordedEvents = events.map (event) ->
			newRecords = {}
			for layerPersistentID, layerRecord of event.layerRecords
				if layerPersistentID[0] != "-"
					layerPersistentID = "-" + layerPersistentID
				newRecords[layerPersistentID] = layerRecord
			event.layerRecords = newRecords
			return event
		this.startPlaying()


	playSavedRecording: (recordingData, audioURL) =>
		return if this.audio
		this.playRecordedData recordingData
		this.audio = new Audio(audioURL);
		this.audio.addEventListener "ended", () => this.stopPlaying()
		this.audio.play()

	pause: =>
		return unless this.isPlayingBackRecording
		this.pauseTime = window.performance.now()
		cancelAnimationFrame this.animationRequest

	unpause: =>
		return unless this.pauseTime
		this.basePlaybackTime += window.performance.now() - this.pauseTime
		this.pauseTime = null
		this.play window.performance.now()

	clear: =>
		this.recordedEvents = []
		this.recorder?.clear()
		this.ignoredPersistentIDs.clear()

	startPlaying: =>
		return if this.isRecording or this.isPlayingBackRecording

		this.basePlaybackTime = window.performance.now()
		this.lastAppliedTime = -1
		this.isPlayingBackRecording = true

		this.playingLayer = new TextLayer
			parent: rootLayer
			x: Align.left(40)
			y: Align.bottom(-53)
			fontSize: 32
			autoSize: true
			color: kaColors.cs1
			text: "Playing…"
			visible: false

		this.play this.basePlaybackTime

		return unless this.recorder
		this.recorder.getBuffer (buffers) =>
			newSource = this.audioContext.createBufferSource()
			newBuffer = this.audioContext.createBuffer 2, buffers[0].length, this.audioContext.sampleRate
			newBuffer.getChannelData(0).set buffers[0]
			newBuffer.getChannelData(1).set buffers[1]
			newSource.buffer = newBuffer
			newSource.addEventListener "ended", (event) => this.stopPlaying()
			newSource.connect this.audioContext.destination
			newSource.start 0

	play: (timestamp) =>
		pauseAtEndOfLoop = 2000
		dt = if this.shouldLoop
			(timestamp - this.basePlaybackTime) % (this.recordedEvents[this.recordedEvents.length - 1].time + pauseAtEndOfLoop)
		else
			timestamp - this.basePlaybackTime

		if this.lastAppliedTime > dt
			for layer in this.relevantLayerGetter()
				layer.destroy() if layer.persistentID
			this.lastAppliedTime = -1

		# Find the relevant event...
		for event in this.recordedEvents
			# We'll play the soonest event we haven't already played.
			if event.time > this.lastAppliedTime and event.time < dt
				relevantLayers = this.relevantLayerGetter()
				# Found it! Apply each layer's record:
				for layerPersistentID in Object.keys(event.layerRecords).sort()
					layerRecord = event.layerRecords[layerPersistentID]
					# Find the live layer layer that corresponds to this.
					# TODO: something less stupid slow... if it ends up being necessary.
					persistentIDComponents = layerPersistentID.split("/").map (component) -> parseInt(component)
					basePersistentID = persistentIDComponents[0]
					continue if this.ignoredPersistentIDs.has(basePersistentID)
					workingLayer = relevantLayers.find (testLayer) ->
						testLayer.persistentID == basePersistentID


					# What if the base persistent layer doesn't exist? i.e. a layer was added during the recording?
					if (not workingLayer) and persistentIDComponents.length == 1
						# For now assume it's a BlockLens.
						args = Object.assign {}, layerRecord.props
						Object.assign args, layerRecord.state
						args.persistentID = basePersistentID
						args.parent = canvas
						workingLayer = new BlockLens args

						relevantLayers = this.relevantLayerGetter() # Recompute working set of layers...

					for index in persistentIDComponents[1..]
						workingLayer = workingLayer.children.find (child) ->
							child.index == index
					workingLayer.style.cssText = layerRecord.style
					workingLayer.props = layerRecord.props
					if layerRecord.state
						workingLayer.applyState layerRecord.state

				# Clean up all persistent IDs that don't appear in the list.
				for layer in relevantLayers when layer.persistentID <= this.highestIDToTouchInRecordings # < 0 here coupled with recording-created namespacing.
					if !event.persistentIDs.has(layer.persistentID) and layer.visible
						layer.visible = false

				this.lastAppliedTime = event.time

				if event == this.recordedEvents[this.recordedEvents.length - 1] and not this.shouldLoop
					this.isPlayingBackRecording = false
					return
				# else
					# break
		this.animationRequest = requestAnimationFrame this.play

	stopPlaying: =>
		this.isPlayingBackRecording = false
		return if not this.animationRequest
		this.playingLayer.destroy()
		if this.audio
			this.audio.pause()
			this.audio = null
		
		cancelAnimationFrame this.animationRequest

		if this.recordedEvents.length > 0
			lastEvent = this.recordedEvents[this.recordedEvents.length - 1]
			lastEvent.persistentIDs.forEach (persistentID) =>
				this.ignoredPersistentIDs.add	persistentID

	startRecording: (skipAudio) =>
		this.recordingLayer = new TextLayer
			parent: rootLayer
			x: Align.left(40)
			y: Align.bottom(-53)
			fontSize: 32
			autoSize: true
			color: kaColors.humanities1
			visible: false
			text: "Recording…"

		this.isRecording = true
		actuallyStartRecording = =>
			this.clear()
			this.baseRecordingTime = window.performance.now()
			this.record this.baseRecordingTime

		if navigator.getUserMedia and not skipAudio
			navigator.getUserMedia({audio: true}, (stream) =>
				input = this.audioContext.createMediaStreamSource stream
				this.recorder = new RecorderUtility(input)
				this.recorder.record()
				actuallyStartRecording()
			, (error) =>
				print "Audio input error: #{error.name}"
				actuallyStartRecording()
			)
		else
			actuallyStartRecording()

	stopRecording: =>
		this.recordingLayer?.destroy()
		this.isRecording = false
		this.recorder?.stop()
		this.highestIDToTouchInRecordings = canvas.nextPersistentID - 1

	downloadRecording: =>
		recordingFilename = new Date().toLocaleString()
		exportEvents = () =>
			eventsJSON = JSON.stringify(this.recordedEvents, (key, value) ->
				if key == "persistentIDs"
					return Array.from(value)
				else if value instanceof Color
					return value.toRgbString()
				else
					return value
			)
			eventsBlob = new Blob [eventsJSON], {type: "application/json"}
			this.saveData eventsBlob, recordingFilename + '.json'

		if this.recorder
			this.recorder.exportWAV (blob) =>
				this.saveData blob, recordingFilename + '.wav'
				exportEvents()
		else
			exportEvents()


	saveData: (blob, fileName) =>
		a = document.createElement "a"
		document.body.appendChild a
		a.style = "display: none";
		url = window.URL.createObjectURL(blob)
		a.href = url
		a.download = fileName
		a.click()
		window.URL.revokeObjectURL(url)

	recordingIDForLayer: (layer) =>
		# TODO: cache?
		if layer.persistentID then return layer.persistentID
		path = layer.index
		currentLayer = layer.parent
		while currentLayer and currentLayer != canvas
			currentLayerComponent = currentLayer.persistentID || currentLayer.index
			path = "#{currentLayerComponent}/#{path}"
			return path if currentLayer.persistentID
			currentLayer = currentLayer.parent

	record: (timestamp) =>
		return unless this.isRecording

		layerRecords = {}
		layerRecordCount = 0
		persistentIDs = new Set
		for layer in this.relevantLayerGetter()
			continue if layer.skipRecording
			recordingID = this.recordingIDForLayer(layer)
			continue unless recordingID

			# Find the last time this layer appeared in our recording.
			lastLayerRecord = null
			for recordedEvent in this.recordedEvents by -1
				lastLayerRecord = recordedEvent.layerRecords[recordingID]
				break if lastLayerRecord

			props = layer.props
			# Here assuming that the state can't change if the style doesn't change. Not a great long-term assumption.
			if !lastLayerRecord or !deepEqual(lastLayerRecord.props, props)
				layerRecords[recordingID] =
					props: props
					style: layer.style.cssText # We write down both props and style because some style stuff is not captured in props. This is super wasteful.
					state: layer.getState?()
				layerRecordCount += 1

			persistentIDs.add layer.persistentID if layer.persistentID

		if layerRecordCount > 0
			event =
				time: timestamp - this.baseRecordingTime
				layerRecords: layerRecords
				persistentIDs: persistentIDs
			this.recordedEvents.push event

		requestAnimationFrame this.record

recorder = new Recorder ->
	result = canvas.descendants
	result.push(canvas)
	return result

window.cantorRecorder = recorder

# Other modes include "recordYourOwn" and "playThrough"
cantorMode = "autoplay"

bottomBar = new Layer
	parent: rootLayer
	x: 0
	y: rootLayer.height - 120
	width: rootLayer.width
	backgroundColor: ""

buttonText = (text) -> "<div style='font-family: ProximaNova, Helvetica, sans-serif; color: #{kaColors.math1}; font-size: 36px; text-align: center; margin: 8% 0%'>#{text}</div>"

resumePlayback = new GlobalButton
	parent: bottomBar
	x: 20
	y: 30
	borderColor: '#BABEC2'
	borderWidth: 1
	opacity: 0
	action: () ->
		for layer in recorder.relevantLayerGetter()
			layer.destroy() if layer.persistentID
		recorder.ignoredPersistentIDs = new Set()
		recorder.playRecordedData recorder.lastPlayedRecordedData
		resumePlayback.animate
			opacity: 0
			options:
				time: 0.1
resumePlayback.width = 175
resumePlayback.height = 70
resumePlayback.html = buttonText "Restart"

recordAndPlayState = "idle"
recordAndPlayButton = new GlobalButton
	parent: bottomBar
	x: 20
	y: 30
	borderColor: '#BABEC2'
	borderWidth: 1
	visible: false
	action: () ->
		if recordAndPlayState == "idle"
			recorder.startRecording()
			recordAndPlayState = "recording"
			recordAndPlayButton.html = buttonText "Stop"
		else if recordAndPlayState == "recording"
			recorder.stopRecording()
			recordAndPlayState = "recorded"
			recordAndPlayButton.html = buttonText "Replay"
		else if recordAndPlayState == "recorded"
			recorder.shouldLoop = true
			recorder.startPlaying()
			recordAndPlayState = "replaying"
			recordAndPlayButton.html = buttonText "Stop"
		else if recordAndPlayState == "replaying"
			recorder.shouldLoop = false
			recorder.stopPlaying()
			recordAndPlayState = "idle"
			recordAndPlayButton.html = buttonText "Record"

recordAndPlayButton.width = 175
recordAndPlayButton.height = 70
recordAndPlayButton.html = buttonText "Record"

window.setCantorMode = (newCantorMode) ->
	resumePlayback.visible = false
	switch newCantorMode
		when "recordYourOwn"
			recordAndPlayButton.visible = true
			recorder.shouldLoop = false
		when "prompt"
			recordAndPlayButton.visible = true
			recordAndPlayButton.html = buttonText "Play"
			recordAndPlayButton.action = () ->
				if not recorder.isPlayingBackRecording
					for layer in recorder.relevantLayerGetter()
						layer.destroy() if layer.persistentID
					recorder.ignoredPersistentIDs = new Set()
					recorder.playSavedRecording window.recordingData, window.recordingAudioURL
			recorder.shouldLoop = false
		else
			recorder.shouldLoop = true
	cantorMode = newCantorMode

rootLayer.onTouchStart (event) ->
	return unless cantorMode == "autoplay" or cantorMode == "prompt"
	return unless recorder.isPlayingBackRecording
	recorder.stopPlaying()
	resumePlayback.animate
		opacity: 1
		options:
			time: 0.2

# Setup

startingOffset = 40 * 60
# setup = ->
# 	for sublayer in canvas.subLayers
# 		continue unless (sublayer instanceof BlockLens)
# 		sublayer.x += startingOffset
# 		sublayer.y += startingOffset

# setup()

# canvasComponent.scrollX = startingOffset
# canvasComponent.scrollY = startingOffset
# grid.x -= startingOffset
# grid.y -= startingOffset
