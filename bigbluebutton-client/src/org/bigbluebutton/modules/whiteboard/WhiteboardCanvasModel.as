package org.bigbluebutton.modules.whiteboard
{
	import com.ryan.geom.FreeTransformManager;
	
	import flash.display.DisplayObject;
	import flash.display.InteractiveObject;
	import flash.display.Shape;
	import flash.display.Sprite;
	import flash.events.FocusEvent;
	import flash.events.KeyboardEvent;
	import flash.events.MouseEvent;
	import flash.events.TextEvent;
	import flash.geom.Point;
	import flash.geom.Rectangle;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	
	import mx.collections.ArrayCollection;
	
	import org.bigbluebutton.common.IBbbCanvas;
	import org.bigbluebutton.common.LogUtil;
	import org.bigbluebutton.main.events.MadePresenterEvent;
	import org.bigbluebutton.modules.whiteboard.business.shapes.DrawObject;
	import org.bigbluebutton.modules.whiteboard.business.shapes.GraphicFactory;
	import org.bigbluebutton.modules.whiteboard.business.shapes.GraphicObject;
	import org.bigbluebutton.modules.whiteboard.business.shapes.WhiteboardConstants;
	import org.bigbluebutton.modules.whiteboard.business.shapes.ShapeFactory;
	import org.bigbluebutton.modules.whiteboard.business.shapes.TextFactory;
	import org.bigbluebutton.modules.whiteboard.business.shapes.TextObject;
	import org.bigbluebutton.modules.whiteboard.events.GraphicObjectFocusEvent;
	import org.bigbluebutton.modules.whiteboard.events.PageEvent;
	import org.bigbluebutton.modules.whiteboard.events.WhiteboardDrawEvent;
	import org.bigbluebutton.modules.whiteboard.events.WhiteboardUpdate;
	import org.bigbluebutton.modules.whiteboard.views.WhiteboardCanvas;
	
	public class WhiteboardCanvasModel {
		public var wbCanvas:WhiteboardCanvas;
		public var ftm:FreeTransformManager = new FreeTransformManager(true);
		
		private var isDrawing:Boolean; 
		private var sending:Boolean = false;
		private var feedback:Shape = new Shape();
		private var latentFeedbacks:Array = new Array();
		private var segment:Array = new Array();
		private var graphicList:Array = new Array();
		
		private var shapeFactory:ShapeFactory = new ShapeFactory();
		private var textFactory:TextFactory = new TextFactory();
		private var bbbCanvas:IBbbCanvas;
		private var lastGraphicObjectSelected:GraphicObject;
		
		private var graphicType:String = WhiteboardConstants.TYPE_SHAPE;
		private var toolType:String = DrawObject.PENCIL;
		private var drawColor:uint = 0x000000;
		private var thickness:uint = 1;
		private var fillOn:Boolean = false;
		private var transparencyOn:Boolean = false;
		private var isPresenter:Boolean;
		
		// represents the max number of 'points' enumerated in 'segment'
		// before sending an update to server. Used to prevent 
		// spamming red5 with unnecessary packets
		private var sendShapeFrequency:uint = 30;	
		private var drawStatus:String = DrawObject.DRAW_START;
		private var textStatus:String = TextObject.TEXT_CREATED;
		private var width:Number;
		private var height:Number;
		
		public function doMouseUp():void{
			if(graphicType == WhiteboardConstants.TYPE_SHAPE) {
				if (isDrawing) {
					/**
					 * Check if we are drawing because when resizing the window, it generates
					 * a mouseUp event at the end of resize. We don't want to dispatch another
					 * shape to the viewers.
					 */
					isDrawing = false;
					
					//check to make sure unnecessary data is not sent
					// ex. a single click when the rectangle tool is selected
					// is hardly classifiable as a rectangle, and should not 
					// be sent to the server
					if(toolType == DrawObject.RECTANGLE || 
						toolType == DrawObject.ELLIPSE) {
						var x:Number = segment[0];
						var y:Number = segment[1];
						var width:Number = segment[segment.length-2]-x;
						var height:Number = segment[segment.length-1]-y;
						if(!(width <= 2 && height <=2))
							sendShapeToServer(DrawObject.DRAW_END);
					} else if (toolType == DrawObject.LINE ||
								toolType == DrawObject.HIGHLIGHTER) {
						if(segment.length > 4)
							sendShapeToServer(DrawObject.DRAW_END);
					} else {
						sendShapeToServer(DrawObject.DRAW_END);
					}
				}
			} else if (graphicType == WhiteboardConstants.TYPE_SELECTION) {
				//(lastGraphicObjectSelected as Sprite).stopDrag();
			}
		}
		
		private var objCount:int = 0;
		
		private function sendShapeToServer(status:String):void {
			if (segment.length == 0) return;
			
			var dobj:DrawObject = shapeFactory.createDrawObject(this.toolType, segment, this.drawColor, this.thickness,
				this.fillOn, this.transparencyOn);
			//dobj.setGraphicID(shapeID);
			
			if(dobj.getGraphicID() == WhiteboardConstants.ID_UNASSIGNED)
				dobj.setGraphicID("-1");
			
			switch (status) {
				case DrawObject.DRAW_START:
					dobj.status = DrawObject.DRAW_START;
					drawStatus = DrawObject.DRAW_UPDATE;
					break;
				case DrawObject.DRAW_UPDATE:
					dobj.status = DrawObject.DRAW_UPDATE;								
					break;
				case DrawObject.DRAW_END:
					dobj.status = DrawObject.DRAW_END;
					drawStatus = DrawObject.DRAW_START;
					break;
			}
			
			LogUtil.error("SEGMENT LENGTH = [" + segment.length + "] STATUS = [" + dobj.status + "]");
			
			if (this.toolType == DrawObject.PENCIL ||
				this.toolType == DrawObject.ERASER) {
				dobj.status = DrawObject.DRAW_END;
				drawStatus = DrawObject.DRAW_START;
				segment = new Array();	
				var xy:Array = wbCanvas.getMouseXY();
				segment.push(xy[0], xy[1]);
			}
			
			wbCanvas.sendGraphicToServer(dobj, WhiteboardDrawEvent.SEND_SHAPE);			
		}
		
		private function sendTextToServer(status:String, obj:TextObject):void {
			var tobj:TextObject = textFactory.makeTextObject(obj);
			//LogUtil.error("Step 1: " + tobj.x + "," + tobj.y);
			//tobj.setGraphicID("" + objCount++);
			if(tobj.getGraphicID() == WhiteboardConstants.ID_UNASSIGNED)
				tobj.setGraphicID("-1");
			
			switch (status) {
				case TextObject.TEXT_CREATED:
					tobj.status = TextObject.TEXT_CREATED;
					textStatus = TextObject.TEXT_UPDATED;
					break;
				case TextObject.TEXT_UPDATED:
					tobj.status = TextObject.TEXT_UPDATED;
					break;
				case TextObject.TEXT_PUBLISHED:
					tobj.status = TextObject.TEXT_PUBLISHED;
					textStatus = TextObject.TEXT_CREATED;
					break;
			}	
			
			wbCanvas.sendGraphicToServer(tobj, WhiteboardDrawEvent.SEND_TEXT);			
		}
		
		public function doMouseDown(mouseX:Number, mouseY:Number):void{
			if(graphicType == WhiteboardConstants.TYPE_SHAPE) {
				
				isDrawing = true;
				drawStatus = DrawObject.DRAW_START;
				segment = new Array();
				segment.push(mouseX);
				segment.push(mouseY);
			} else if(graphicType == WhiteboardConstants.TYPE_SELECTION) {
			
				var objs:Array = 
					getGraphicObjectsUnderPoint(mouseX, mouseY);		
				var graphics:Array = filterGraphicObjects(objs);
				
				LogUtil.debug("There are " + graphics.length + " objects" +
					"under your mouse.");						

				var topMostObject:GraphicObject = //getTopMostObject(graphics) as GraphicObject;
									graphics[0] as GraphicObject;
				LogUtil.debug("!!!TOP MOST OBJECT: " + topMostObject.getProperties());
				//(topMostObject as Sprite).startDrag();
				//ftm.activateSprite(topMostObject as DisplayObject);
				//lastGraphicObjectSelected = topMostObject;
				//lastGraphicObjectSelected = topMostObject;
				//ftm.onDispObjMDown(null);
				/*for(var i:int = 0; i <= graphics.length; i++) {
					var currObj:DisplayObject = graphics[i];
					var index:int = wbCanvas.stage.getChildIndex(currObj);
					LogUtil.debug(index + " " + currObj.x + "," + currObj.y);
				}*/
			}
		}
		
		public function doMouseDoubleClick(mouseX:Number, mouseY:Number):void {
			if(graphicType == WhiteboardConstants.TYPE_TEXT) {
				LogUtil.error("double click received at " + mouseX + "," + mouseY);
				var tobj:TextObject = textFactory.cloneTextObject(
					"TEST", 0x000000, 0x000000, false, mouseX, mouseY);
				sendTextToServer(TextObject.TEXT_CREATED, tobj);
			}
		}
		
		public function doMouseMove(mouseX:Number, mouseY:Number):void{
			if(graphicType == WhiteboardConstants.TYPE_SHAPE) {
				if (isDrawing){
					segment.push(mouseX);
					segment.push(mouseY);
					if (segment.length > sendShapeFrequency) {
						sendShapeToServer(drawStatus);
					}
				}
			}
		}
		
		public function drawGraphic(event:WhiteboardUpdate):void{
			var o:GraphicObject = event.data;
			var recvdShapes:Boolean = event.recvdShapes;
			
			if(o.getGraphicType() == WhiteboardConstants.TYPE_SHAPE) {
				var dobj:DrawObject = o as DrawObject;
				drawShape(dobj, recvdShapes);	
				
			} else if(o.getGraphicType() == WhiteboardConstants.TYPE_TEXT) { 
				/*var tobj:TextObject = o as TextObject;
				drawText(tobj, recvdShapes);	
				if(tobj.status == TextObject.TEXT_PUBLISHED)
					ftm.registerSprite(tobj);*/
			}
		}
		
		private function drawShape(o:DrawObject, recvdShapes:Boolean):void{		
			LogUtil.debug("Got shape [" + o.getType() + " " + o.status + "]");
			switch (o.status) {
				case DrawObject.DRAW_START:
					addNewShape(o);														
					break;
				case DrawObject.DRAW_UPDATE:
				case DrawObject.DRAW_END:
					if (graphicList.length == 0 || 
						o.getType() == DrawObject.PENCIL ||
						o.getType() == DrawObject.ERASER ||
						recvdShapes) {
						addNewShape(o);
					} else {
						removeLastGraphic();		
						addNewShape(o);
					}					
					break;
			}        
		}
		
		private function drawText(o:TextObject, recvdShapes:Boolean):void{		
			LogUtil.debug("Got text [" + o.text + " " + 
				o.status + " " + o.x + " " + o.y + "]");
			switch (o.status) {
				case TextObject.TEXT_CREATED:
					addNewText(o);														
					break;
				case TextObject.TEXT_UPDATED:
				case TextObject.TEXT_PUBLISHED:
					if (graphicList.length == 0 || recvdShapes) {
						if(!isPresenter)
							addNewText(o);
					} else {
						if(!isPresenter) {
							removeLastGraphic();
							addNewText(o);
						}
					}					
					break;
			}        
		}
		
		private function addNewShape(o:DrawObject):void {
			//LogUtil.debug("Adding new shape " + graphicList.length);
			var dobj:DrawObject = shapeFactory.makeShape(o);
			wbCanvas.addGraphic(dobj);
			/*if(dobj.status == DrawObject.DRAW_END && 
				(dobj.getType() == DrawObject.ELLIPSE ||
				dobj.getType() == DrawObject.RECTANGLE)) {
				LogUtil.debug("ADDED TO FTM " + dobj.getProperties());
					ftm.registerSprite(dobj, { minW:50, maxW:500 });
			}*/
			graphicList.push(dobj);
		}
		
		private function addNewText(t:TextObject):void {
			LogUtil.debug("Adding new text " + t.x + "," + t.y);
			var tobj:TextObject = textFactory.makeTextObject(t);
			LogUtil.debug("FINAL " + tobj.x + "," + tobj.y);
			
			if(isPresenter) {
				if(t.status == TextObject.TEXT_CREATED) {
					tobj.multiline = true;
					tobj.wordWrap = true;
					wbCanvas.addGraphic(tobj);
					graphicList.push(tobj);
					tobj.autoSize = TextFieldAutoSize.LEFT;
					tobj.makeEditable(true);
					tobj.registerListeners(textObjGainedFocus,
						textObjLostFocus,
						textObjTextListener,
						textObjDeleteListener);
					wbCanvas.stage.focus = tobj;
					tobj.stage.focus = tobj;
					//LogUtil.debug("ADDED TO FTM " + tobj.getProperties());
					//ftm.registerSprite(tobj);	
					
				}else if(tobj.status == TextObject.TEXT_PUBLISHED) {
						
				}
			} else {
				tobj.multiline = true;
				tobj.wordWrap = true;
				tobj.autoSize = TextFieldAutoSize.LEFT;
				tobj.makeEditable(false);
				wbCanvas.addGraphic(tobj);
				graphicList.push(tobj);
			}
		}
		
		public function setGraphicType(type:String):void{
			this.graphicType = type;
		}
		
		public function setTool(s:String):void{
			/*if(s == DrawObject.HIGHLIGHTER) {
				if (drawColor == 0x000000 ||
					drawColor == 0xFFFFFF) drawColor = 0xCCFF00;	
			}*/
			this.toolType = s;
		}
		
		public function changeColor(color:uint):void{
			drawColor = color;
		}
		
		public function changeThickness(thickness:uint):void{
			this.thickness = thickness;
		}
		
		public function toggleFill():void{
			fillOn = !fillOn;
		}
		
		public function toggleTransparency():void{
			transparencyOn = !transparencyOn;
		}
		
		public function setFill(fill:Boolean):void{
			this.fillOn = fill;
		}
		
		public function setTransparent(transp:Boolean):void{
			this.transparencyOn = transp;
		}
		
		private function removeLastGraphic():void {
			var gobj:GraphicObject = graphicList.pop() as GraphicObject;
			if(gobj.getGraphicType() == WhiteboardConstants.TYPE_TEXT) {
				(gobj as TextObject).makeEditable(false);
				(gobj as TextObject).registerListeners(textObjGainedFocus,
					textObjLostFocus,
					textObjTextListener,
					textObjDeleteListener);
			}	
			wbCanvas.removeGraphic(gobj as DisplayObject);
		}
		
		private function removeLastShape():void {
			for(var i:int = graphicList.length-1; i >= 0; i--) {
				var currGobj:GraphicObject = graphicList[i];
				if(currGobj.getGraphicType() == WhiteboardConstants.TYPE_SHAPE) {
					var dobj:DrawObject = currGobj as DrawObject;
					wbCanvas.removeGraphic(dobj as DisplayObject);
				}
			}
		}
		
		private function removeLastText():void {
			for(var i:int = graphicList.length-1; i >= 0; i--) {
				var currGobj:GraphicObject = graphicList[i];
				if(currGobj.getGraphicType() == WhiteboardConstants.TYPE_TEXT) {
					var tobj:TextObject = currGobj as TextObject;
					wbCanvas.removeGraphic(tobj as DisplayObject);	
				}
			}
		}
		
		private function getAllShapes():Array {
			var shapes:Array = new Array();
			var count:int = 0;
			for(var i:int = graphicList.length-1; i >= 0; i--) {
				var currGobj:GraphicObject = graphicList[i];
				if(currGobj.getGraphicType() == WhiteboardConstants.TYPE_SHAPE) {
					var dobj:DrawObject = currGobj as DrawObject;
					shapes[count++] = dobj;
				}
			}
			return shapes;
		}
		
		private function getAllTexts():Array {
			var texts:Array = new Array();
			var count:int = 0;
			for(var i:int = graphicList.length-1; i >= 0; i--) {
				var currGobj:GraphicObject = graphicList[i];
				if(currGobj.getGraphicType() == WhiteboardConstants.TYPE_TEXT) {
					var tobj:TextObject = currGobj as TextObject;
					texts[count++] = tobj;
				}
			}
			return texts;
		}
		
		public function clearBoard(event:WhiteboardUpdate = null):void {
			var numGraphics:int = this.graphicList.length;
			for (var i:Number = 0; i < numGraphics; i++){
				removeLastGraphic();
			}
		}
		
		public function undoGraphic():void{
			if (this.graphicList.length > 0) {
				removeLastGraphic();
			}
		}
		
		private function undoLastShape():void {
			for(var i:int = graphicList.length-1; i >= 0; i--) {
				var currGobj:GraphicObject = graphicList[i];
				if(currGobj.getGraphicType() == WhiteboardConstants.TYPE_SHAPE) {
					var dobj:DrawObject = currGobj as DrawObject;
					wbCanvas.removeGraphic(dobj as DisplayObject);
				}
			}
		}
		
		private function undoLastText():void {
			for(var i:int = graphicList.length-1; i >= 0; i--) {
				var currGobj:GraphicObject = graphicList[i];
				if(currGobj.getGraphicType() == WhiteboardConstants.TYPE_TEXT) {
					var tobj:TextObject = currGobj as TextObject;
					wbCanvas.removeGraphic(tobj as DisplayObject);
				}
			}
		}
		
		public function changePage(e:PageEvent):void{
			var page:Number = e.pageNum;
			var graphicObjs:ArrayCollection = e.graphicObjs;
			
			clearBoard();
			for (var i:int = 0; i < graphicObjs.length; i++){
				var o:GraphicObject = graphicObjs.getItemAt(i) as GraphicObject;
				if(o.getGraphicType() == WhiteboardConstants.TYPE_SHAPE)
					drawShape(o as DrawObject, false);
				else if(o.getGraphicType() == WhiteboardConstants.TYPE_TEXT) 
					drawText(o as TextObject, false);	
			}
		}
		
		public function zoomCanvas(width:Number, height:Number):void{
			shapeFactory.setParentDim(width, height);	
			textFactory.setParentDim(width, height);
			this.width = width;
			this.height = height;
			//LogUtil.debug("" + graphicList.length);
			for (var i:int = 0; i < this.graphicList.length; i++){
				redrawGraphic(this.graphicList[i] as GraphicObject, i);
			}				
		}
		
		public function makeTextObjectsEditable(e:MadePresenterEvent):void {
			LogUtil.debug("MADE PRESENTER IS PRESENTER TRUE");
			isPresenter = true;
			var texts:Array = getAllTexts();
			for(var i:int = 0; i < texts.length; i++) {
				(texts[i] as TextObject).makeEditable(true);
				(texts[i] as TextObject).registerListeners(textObjGainedFocus,
					textObjLostFocus,
					textObjTextListener,
					textObjDeleteListener);
			}
			//wbCanvas.stage.addChild(ftm);
		}
		
		public function makeTextObjectsUneditable(e:MadePresenterEvent):void {
			LogUtil.debug("MADE PRESENTER IS PRESENTER FALSE");
			isPresenter = false;
			var texts:Array = getAllTexts();
			for(var i:int = 0; i < texts.length; i++) {
				(texts[i] as TextObject).makeEditable(false);
				(texts[i] as TextObject).deregisterListeners(textObjGainedFocus,
					textObjLostFocus,
					textObjTextListener,
					textObjDeleteListener);

			}
		}
		
		public function textObjDeleteListener(event:KeyboardEvent):void {
			// check for special conditions
			if(event.charCode == 127 || // 'delete' key
				event.charCode == 8 || // 'bkspace' key
				event.charCode == 13) { // 'enter' key
				var sendStatus:String = TextObject.TEXT_UPDATED;
				var tobj:TextObject = event.target as TextObject;	
				var updatedObj:TextObject = textFactory.createTextObject(
					tobj.text,
					tobj.textColor,
					tobj.backgroundColor,
					tobj.background,
					tobj.x,
					tobj.y);
				if(event.charCode == 13) {
					sendStatus = TextObject.TEXT_PUBLISHED;
					LogUtil.debug("Text published to: " +  tobj.text);
					wbCanvas.stage.focus = null;
					tobj.stage.focus = null;
				}
				sendTextToServer(sendStatus, updatedObj);	
			} 	
		}
		
		public function textObjTextListener(event:TextEvent):void {
			var sendStatus:String = TextObject.TEXT_UPDATED;
			var tf:TextObject = event.target as TextObject;	
			var updatedObj:TextObject = textFactory.createTextObject(
				tf.text,
				tf.textColor,
				tf.backgroundColor,
				tf.background,
				tf.x,
				tf.y);
			sendTextToServer(sendStatus, updatedObj);	
		}
		
		public function textObjGainedFocus(event:FocusEvent):void {
			var tf:TextObject = event.currentTarget as TextObject;
			wbCanvas.stage.focus = tf;
			tf.stage.focus = tf;
			var e:GraphicObjectFocusEvent = 
				new GraphicObjectFocusEvent(GraphicObjectFocusEvent.OBJECT_SELECTED);
			e.data = tf;
			wbCanvas.dispatchEvent(e);
		}
		
		public function textObjLostFocus(event:FocusEvent):void {
			var tf:TextObject = event.target as TextObject;	
			var updatedObj:TextObject = textFactory.createTextObject(
				tf.text,
				tf.textColor,
				tf.backgroundColor,
				tf.background,
				tf.x,
				tf.y);
			sendTextToServer(TextObject.TEXT_PUBLISHED, updatedObj);	
			LogUtil.debug("Text published to: " +  tf.text);
			var e:GraphicObjectFocusEvent = 
				new GraphicObjectFocusEvent(GraphicObjectFocusEvent.OBJECT_DESELECTED);
			e.data = tf;
			wbCanvas.dispatchEvent(e);
		}
		
		private function redrawGraphic(gobj:GraphicObject, objIndex:int):void {
			if(gobj.getGraphicType() == WhiteboardConstants.TYPE_SHAPE) {
				var origDobj:DrawObject = gobj as DrawObject;
				wbCanvas.removeGraphic(origDobj);
				origDobj.graphics.clear();
				var dobj:DrawObject =  shapeFactory.makeShape(origDobj);
				dobj.setGraphicID(origDobj.getGraphicID());
				dobj.status = origDobj.status;
				wbCanvas.addGraphic(dobj);
				graphicList[objIndex] = dobj;
				/*LogUtil.debug("index " + objIndex + " " + 
					(graphicList[objIndex] as GraphicObject).getProperties() );*/
			} else if(gobj.getGraphicType() == WhiteboardConstants.TYPE_TEXT) {
				var origTobj:TextObject = gobj as TextObject;
				wbCanvas.removeGraphic(origTobj);
				/*var tobj:TextObject = textFactory.makeTextObject(origTobj);
				tobj.setGraphicID(origTobj.getGraphicID());
				tobj.status = origTobj.status;*/
				wbCanvas.addGraphic(origTobj);
			}
			
		}
		
		private function getIndexOfGobj(gobj:GraphicObject):int {
			for(var i:int = 0; i < graphicList.length; i++) {
				var currObj:GraphicObject = graphicList[i] as GraphicObject;
				if(currObj == gobj) return i;
			}
			return -1;
		}
		
		private function getGraphicObjectsUnderPoint(xf:Number, yf:Number):Array {
			var x:Number = 
				GraphicFactory.denormalize(
					GraphicFactory.normalize(xf,
						textFactory.getParentWidth()), textFactory.getParentWidth());
			var y:Number = 
				GraphicFactory.denormalize(
					GraphicFactory.normalize(yf,
					textFactory.getParentHeight()), textFactory.getParentHeight());
			var point:Point = new Point(x,y);
			point = wbCanvas.localToGlobal(point);
			
			var d:Sprite = new Sprite();
			//d.startDrag();
			//d.buttonMode = true;
			d.graphics.lineStyle(1, 0x00FF00);
			d.graphics.beginFill(0xFF00FF,0.6);
			d.graphics.drawRect(point.x, point.y, 15, 15);
			wbCanvas.stage.addChild(d);
			
			ftm.registerSprite(d);
			
			return wbCanvas.parentApplication.getObjectsUnderPoint(point);
		}
		
		private function filterGraphicObjects(objs:Array):Array {
			return objs.filter(
				function callback(item:*, index:int, array:Array):Boolean
				{
					return item is GraphicObject;
				}
			);
		}
		
		private function getTopMostObject(objs:Array):Object {
			//var numChildren:int = wbCanvas.parentApplication.getChildren().length;
			var topMostObj:Object;

			for(var i:int = objs.length-2; i >= 0; i--) {
				var firstIndex:int = 
					wbCanvas.parentApplication.getChildIndex(objs[i]);
				var secondIndex:int = 
					wbCanvas.parentApplication.getChildIndex(objs[i+1]);
				topMostObj = 
					(firstIndex > secondIndex) ? firstIndex : secondIndex;
			}
			
			return topMostObj;
		}
		
		public function isPageEmpty():Boolean {
			return graphicList.length == 0;
		}

	}
}