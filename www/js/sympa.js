function showMDN(el) {
	var pre = $(el).parent().find('pre').eq(0);
	if(!pre.length) return;
	var mdn = pre.html();
	return showMessage(mdn.replace(/ /g, '&nbsp;').replace(/\t/g, '&nbsp;&nbsp;&nbsp;&nbsp;').replace(/\n/g, '<br />'), true);
}

function showMessage(message, ishtml) { // if ishtml not set then \n to <br /> transformation is applied to message
	if(!ishtml) message = message.replace(/\n/g, '<br />');
	
	var block = $('<div id="ErrorBlock" />').prependTo('body');
	var msg = $('<div id="ErrorMsg" />').prependTo('body');
	var ctn = $('<div class="messageContent" />').appendTo(msg).append(message);
	
	var fs = $('<fieldset />').appendTo($('<form />').appendTo(msg));
	
	$('<input type="button" class="MainMenuLinks" value="OK" />').appendTo(fs).on('click', function() {
		$('#ErrorBlock').remove();
		$('#ErrorMsg').remove();
	});
	
	return ctn;
}

// To confirm archives deletion
// NO LONGER USED as of 6.2.17.
function dbl_confirm(my_form, my_message,my_message2) {
  if (confirm(my_message)) {
      if (confirm(my_message2)) {
        my_form.zip.value = "1";
      }
  }else{
    return false;
  }
}

// To confirm on a link (A HREF)
function refresh_mom_and_die() {
  url = window.opener.location.href;
  if (url.indexOf('logout') > -1 ) {
    url = sympa.home_url;
  }
  window.opener.location = url;
  self.close();
}

function setnsubmit(element, attribute, value, formid) {
	$('#' + element).attr(attribute, value);
	$('#' + formid).submit();
}

function showhide(div) {
	$('#' + div).toggle();
}

// NO LONGER USED as of Sympa 6.2.17.
function show(div) {
	$('#' + div).show();
}

// NO LONGER USED as of Sympa 6.2.17.
function hide(div) {
	$('#' + div).hide();
}

function hideError() {
	$('#ErrorBlock').remove();
	$('#ErrorMsg').remove();
}

// To confirm a form submition
// NO LONGER USED as of 6.2.17.
function request_confirm(my_message) {
	return !!confirm(my_message);
}

// To confirm on a link (A HREF)
// NO LONGER USED as of 6.2.17.
function request_confirm_link(my_url, my_message) {
	if(confirm(my_message)) top.location = my_url;
}

function GetCookie(name) {
	var cookies = document.cookies.split('; ');
	
	for(var i=0; i<cookies.length; i++) {
		var parts = cookies[i].split('=');
		var key = parts.shift();
		if(key != name) continue;
		
		return parts.join('='); // In case of =s in value
	}
	
	return null;
}  

function toggle_selection(myfield) {
	if(typeof myfield.length == 'undefined') myfield = [myfield];
	$.each(myfield, function() {
		$(this).prop('checked',  !$(this).is(':checked'));
    });
}

function chooseColorNumber(cn, cv) {
    $('#custom_color_number').val(cn);
    if (cv) {
      $('#custom_color_value').val(cv);
      $('#custom_color_value').trigger('change');
    }
}

// check if rejecting quietly spams TODO
function check_reject_spam(form,warningId) {
	if(form.elements['iConfirm'].checked) return true;
	
	if(form.elements['message_template'].options[form.elements['message_template'].selectedIndex].value ==  'reject_quiet') return true;
	
	$('#' + warningId).show();
	return false;
}

// To check at least one checkbox checked
function checkbox_check_topic(form, warningId) {
	if($(form).find('input[name^="topic_"]:checked').length) return true;
	
	$('#' + warningId).show();
	return false;
}

function set_select_value(s, v) {
	$(s).val(v);
}

//launch a search by message Id
function searched_by_msgId(id) {
	var f = document.forms["log_form"];
	
	set_select_value(f.elements["type"], 'all_actions');
	
	set_select_value(f.elements["target_type"], 'msg_id');
	
	f.elements["target"].value = id;
	f.submit();
}

//reset all field in log form.
function clear_log_form() {
	var f = document.forms["log_form"];
	
	set_select_value(f.elements["type"], 'all_actions');
	
	set_select_value(f.elements["target_type"], 'msg_id');
	
	f.elements["target"].value = '';

	f.elements["date_from"].value = '';
	f.elements["date_to"].value = '';
	f.elements["ip"].value = '';
}

//set a form field value to empty string. It uses the value of the field whose id is given
// as argument as a control to perform this operation or not.
function empty_field(target_field, control_field) {
	if (document.getElementById(control_field).value == 'false'){
		document.getElementById(control_field).value = 'true';
		document.getElementById(target_field).value = '';
	}
}

//to hide menu

function afficheId(baliseId,baliseId2)
  {
  if (document.getElementById && document.getElementById(baliseId) != null)
    {
    document.getElementById(baliseId).style.visibility='visible';
    document.getElementById(baliseId).style.display='block';
    }
  if (document.getElementById(baliseId2) != null)
    {
    document.getElementById(baliseId2).style.margin='0 0 0 25%';
    }
  }

function cacheId(baliseId,baliseId2)
  {
  if (document.getElementById && document.getElementById(baliseId) != null)
    {
    document.getElementById(baliseId).style.visibility='hidden';
    document.getElementById(baliseId).style.display='none';
    }
  if (document.getElementById(baliseId2) != null)
    {
    document.getElementById(baliseId2).style.margin='0 0 0 0';
    }
  
  }

cacheId('contenu','Stretcher');
// if JavaScript is available, hide the content on the page load.
// Without JavaScript, content will be display.


// Pour afficher/cacher avec timeout des commandes d'admin dans la liste des listes
function affiche(id) {
  document.getElementById(id).style.display = '';
  if(document.getElementById(id).to) window.clearTimeout(document.getElementById(id).to);
}
function cache(e,id) {
  var relTarg = e.relatedTarget || e.toElement;
  if(!isChildOf(relTarg,document.getElementById('admin_[% listname %]'))) {
    document.getElementById(id).to = window.setTimeout(function() {
      document.getElementById(id).style.display = 'none';
    }, 1000);
  }
}
function isChildOf(child,par) {
  while(child!=document) {
    if(child==par) { return true; }
    child = child.parentNode;
  }
  return false;
}
// Fin afficher/cacher avec timeout des commandes d'admin dans la liste des listes



// Here are some boring utility functions. The real code comes later.

function hexToRgb(hex_string, default_)
{
    if (default_ == undefined)
    {
        default_ = null;
    }

    if (hex_string.substr(0, 1) == '#')
    {
        hex_string = hex_string.substr(1);
    }
    
    var r;
    var g;
    var b;
    if (hex_string.length == 3)
    {
        r = hex_string.substr(0, 1);
        r += r;
        g = hex_string.substr(1, 1);
        g += g;
        b = hex_string.substr(2, 1);
        b += b;
    }
    else if (hex_string.length == 6)
    {
        r = hex_string.substr(0, 2);
        g = hex_string.substr(2, 2);
        b = hex_string.substr(4, 2);
    }
    else
    {
        return default_;
    }
    
    r = parseInt(r, 16);
    g = parseInt(g, 16);
    b = parseInt(b, 16);
    if (isNaN(r) || isNaN(g) || isNaN(b))
    {
        return default_;
    }
    else
    {
        return {r: r / 255, g: g / 255, b: b / 255};
    }
}

function rgbToHex(r, g, b, includeHash)
{
    r = Math.round(r * 255);
    g = Math.round(g * 255);
    b = Math.round(b * 255);
    if (includeHash == undefined)
    {
        includeHash = true;
    }
    
    r = r.toString(16);
    if (r.length == 1)
    {
        r = '0' + r;
    }
    g = g.toString(16);
    if (g.length == 1)
    {
        g = '0' + g;
    }
    b = b.toString(16);
    if (b.length == 1)
    {
        b = '0' + b;
    }
    return ((includeHash ? '#' : '') + r + g + b).toUpperCase();
}

var arVersion = navigator.appVersion.split("MSIE");
var version = parseFloat(arVersion[1]);

function fixPNG(myImage)
{
    if ((version >= 5.5) && (version < 7) && (document.body.filters)) 
    {
        var node = document.createElement('span');
        node.id = myImage.id;
        node.className = myImage.className;
        node.title = myImage.title;
        node.style.cssText = myImage.style.cssText;
        node.style.setAttribute('filter', "progid:DXImageTransform.Microsoft.AlphaImageLoader"
                                        + "(src=\'" + myImage.src + "\', sizingMethod='scale')");
        node.style.fontSize = '0';
        node.style.width = myImage.width.toString() + 'px';
        node.style.height = myImage.height.toString() + 'px';
        node.style.display = 'inline-block';
        return node;
    }
    else
    {
        return myImage.cloneNode(false);
    }
}

function trackDrag(node, handler)
{
    function fixCoords(ev)
    {
        var e = ev.originalEvent.changedTouches
            ? ev.originalEvent.changedTouches[0] : ev;
        x = e.pageX - $(node).offset().left;
        y = e.pageY - $(node).offset().top;
        if (x < 0) x = 0;
        if (y < 0) y = 0;
        if (x > node.offsetWidth - 1) x = node.offsetWidth - 1;
        if (y > node.offsetHeight - 1) y = node.offsetHeight - 1;
        return {x: x, y: y};
    }
    var _pointer = (function()
    {
        if (window.navigator.pointerEnabled) // Pointer events (IE11+)
        {
            return {down: 'pointerdown', move: 'pointermove', up: 'pointerup'};
        }
        else if ('ontouchstart' in window)   // Touch events
        {
            return {down: 'touchstart', move: 'touchmove', up: 'touchend'};
        }
        else
        {
            return {down: 'mousedown', move: 'mousemove', up: 'mouseup'};
        }
    })();
    function mouseDown(ev)
    {
        var coords = fixCoords(ev);
        var lastX = coords.x;
        var lastY = coords.y;
        handler(coords.x, coords.y);

        function moveHandler(ev)
        {
            var coords = fixCoords(ev);
            if (coords.x != lastX || coords.y != lastY)
            {
                lastX = coords.x;
                lastY = coords.y;
                handler(coords.x, coords.y);
            }
        }
        function upHandler(ev)
        {
            $(document).off(_pointer.up, upHandler);
            $(document).off(_pointer.move, moveHandler);
            $(node).on(_pointer.down, mouseDown);
        }
        $(document).on(_pointer.up, upHandler);
        $(document).on(_pointer.move, moveHandler);
        $(node).off(_pointer.down, mouseDown);
        if (ev.preventDefault) ev.preventDefault();
    }
    $(node).on(_pointer.down, mouseDown);
}

// This copyright statement applies to the following two functions,
// which are taken from MochiKit.
//
// Copyright 2005 Bob Ippolito <bob@redivi.com>
//
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject
// to the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

function hsvToRgb(hue, saturation, value)
{
    var red;
    var green;
    var blue;
    if (value == 0.0)
    {
        red = 0;
        green = 0;
        blue = 0;
    }
    else
    {
        var i = Math.floor(hue * 6);
        var f = (hue * 6) - i;
        var p = value * (1 - saturation);
        var q = value * (1 - (saturation * f));
        var t = value * (1 - (saturation * (1 - f)));
        switch (i)
        {
            case 1: red = q; green = value; blue = p; break;
            case 2: red = p; green = value; blue = t; break;
            case 3: red = p; green = q; blue = value; break;
            case 4: red = t; green = p; blue = value; break;
            case 5: red = value; green = p; blue = q; break;
            case 6: // fall through
            case 0: red = value; green = t; blue = p; break;
        }
    }
    return {r: red, g: green, b: blue};
}

function rgbToHsv(red, green, blue)
{
    var max = Math.max(Math.max(red, green), blue);
    var min = Math.min(Math.min(red, green), blue);
    var hue;
    var saturation;
    var value = max;
    if (min == max)
    {
        hue = 0;
        saturation = 0;
    }
    else
    {
        var delta = (max - min);
        saturation = delta / max;
        if (red == max)
        {
            hue = (green - blue) / delta;
        }
        else if (green == max)
        {
            hue = 2 + ((blue - red) / delta);
        }
        else
        {
            hue = 4 + ((red - green) / delta);
        }
        hue /= 6;
        if (hue < 0)
        {
            hue += 1;
        }
        if (hue > 1)
        {
            hue -= 1;
        }
    }
    return {
        h: hue,
        s: saturation,
        v: value
    };
}

// The real code begins here.
var huePositionImg = document.createElement('img');
huePositionImg.galleryImg = false;
huePositionImg.width = 35;
huePositionImg.height = 11;
huePositionImg.src = sympa.icons_url + '/position.png';
huePositionImg.style.position = 'absolute';

var hueSelectorImg = document.createElement('img');
hueSelectorImg.galleryImg = false;
hueSelectorImg.width = 35;
hueSelectorImg.height = 200;
hueSelectorImg.src = sympa.icons_url + '/h.png';
hueSelectorImg.style.display = 'block';

var satValImg = document.createElement('img');
satValImg.galleryImg = false;
satValImg.width = 200;
satValImg.height = 200;
satValImg.src = sympa.icons_url + '/sv.png';
satValImg.style.display = 'block';

var crossHairsImg = document.createElement('img');
crossHairsImg.galleryImg = false;
crossHairsImg.width = 21;
crossHairsImg.height = 21;
crossHairsImg.src = sympa.icons_url + '/crosshairs.png';
crossHairsImg.style.position = 'absolute';

function makeColorSelector(inputBox)
{
    var rgb, hsv
    
    function colorChanged()
    {
        var hex = rgbToHex(rgb.r, rgb.g, rgb.b);
        var hueRgb = hsvToRgb(hsv.h, 1, 1);
        var hueHex = rgbToHex(hueRgb.r, hueRgb.g, hueRgb.b);
        previewDiv.style.background = hex;
        inputBox.value = hex;
        satValDiv.style.background = hueHex;
        crossHairs.style.left = ((hsv.v*199)-10).toString() + 'px';
        crossHairs.style.top = (((1-hsv.s)*199)-10).toString() + 'px';
        huePos.style.top = ((hsv.h*199)-5).toString() + 'px';
    }
    function rgbChanged()
    {
        hsv = rgbToHsv(rgb.r, rgb.g, rgb.b);
        colorChanged();
    }
    function hsvChanged()
    {
        rgb = hsvToRgb(hsv.h, hsv.s, hsv.v);
        colorChanged();
    }
    
    var colorSelectorDiv = document.createElement('div');
    colorSelectorDiv.style.padding = '15px';
    colorSelectorDiv.style.position = 'relative';
    colorSelectorDiv.style.height = '275px';
    colorSelectorDiv.style.width = '250px';
    
    var satValDiv = document.createElement('div');
    satValDiv.style.position = 'relative';
    satValDiv.style.width = '200px';
    satValDiv.style.height = '200px';
    var newSatValImg = fixPNG(satValImg);
    satValDiv.appendChild(newSatValImg);
    var crossHairs = crossHairsImg.cloneNode(false);
    satValDiv.appendChild(crossHairs);
    function satValDragged(x, y)
    {
        hsv.s = 1-(y/199);
        hsv.v = (x/199);
        hsvChanged();
    }
    trackDrag(satValDiv, satValDragged)
    colorSelectorDiv.appendChild(satValDiv);

    var hueDiv = document.createElement('div');
    hueDiv.style.position = 'absolute';
    hueDiv.style.left = '230px';
    hueDiv.style.top = '15px';
    hueDiv.style.width = '35px';
    hueDiv.style.height = '200px';
    var huePos = fixPNG(huePositionImg);
    hueDiv.appendChild(hueSelectorImg.cloneNode(false));
    hueDiv.appendChild(huePos);
    function hueDragged(x, y)
    {
        hsv.h = y/199;
        hsvChanged();
    }
    trackDrag(hueDiv, hueDragged);
    colorSelectorDiv.appendChild(hueDiv);
    
    var previewDiv = document.createElement('div');
    previewDiv.style.height = '50px'
    previewDiv.style.width = '50px';
    previewDiv.style.position = 'absolute';
    previewDiv.style.top = '225px';
    previewDiv.style.left = '15px';
    previewDiv.style.border = '1px solid black';
    colorSelectorDiv.appendChild(previewDiv);
    
    function inputBoxChanged()
    {
        rgb = hexToRgb(inputBox.value, {r: 0, g: 0, b: 0});
        rgbChanged();
    }
    $(inputBox).change(inputBoxChanged);
    inputBox.size = 8;
    var inputBoxDiv = document.createElement('div');
    inputBoxDiv.style.position = 'absolute';
    inputBoxDiv.style.right = '15px';
    inputBoxDiv.style.top =
        (225 + (25 - (inputBox.offsetHeight/2))).toString() + 'px';
    inputBoxDiv.appendChild(inputBox);
    colorSelectorDiv.appendChild(inputBoxDiv);
    
    inputBoxChanged();
    
    return colorSelectorDiv;
}

function makeColorSelectors(ev)
{
    var inputNodes = document.getElementsByTagName('input');
    var i;
    for (i = 0; i < inputNodes.length; i++)
    {
        var node = inputNodes[i];
        if (node.className != 'color')
        {
            continue;
        }
        var parent = node.parentNode;
        var prevNode = node.previousSibling;
        var selector = makeColorSelector(node);
        parent.insertBefore(selector, (prevNode ? prevNode.nextSibling : null));
    }
}

$(window).on('load', makeColorSelectors);

/* Loading jQuery-UI Datepicker Widget. */
$(function() {
    var options = {
        buttonText:      sympa.calendarButtonText,
        changeMonth:     true,
        changeYear:      true,
        dateFormat:      'dd-mm-yy',
        dayNames:        sympa.dayNames,
        dayNamesMin:     sympa.dayNamesMin,
        firstDay:        sympa.calendarFirstDay,
        monthNamesShort: sympa.monthNamesShort,
        shortYearCutoff: 50,
        showOn:          "button"
    };
    $('#date_deb').datepicker(options);
    $('#date_from').datepicker(options);
    $('#date_fin').datepicker(options);
    $('#date_to').datepicker(options);
});

/* popups config contextual help */
function config_ctxhelp(td) {
	td = $(td);
	if(!td.data('ctx_help')) td.data('ctx_help', td.find('div').eq(0).width(td.closest('table').width()).on('mouseout', function() {
		$(this).hide();
	}));
	td.data('ctx_help').show();
}


// function that hide all hiddenform except one which Id is the function parameter (used in modindex and more)
function toggleDivDisplay(my_message_id) {
	$('div[name="hiddenform"]:not(#' + my_message_id + ')').hide();
	$('#' + my_message_id).show();
}

//hide a div (usually a part of a form) 
function hideform(my_message_id) {
	$('#' + my_message_id).hide();
}

// Show "Please wait..." spinner icon.
$(function() {
	var loadingText =
	$('<h1 id="loadingText"><i class="fa fa-spinner fa-pulse"></i> ' +
		sympa.loadingText + '</h1>');
	$('#loading').append(loadingText);

	$('.heavyWork').on('click', function(){
		$('#loading').show();
		$('#content-inner').hide();
	});
});

// fade effect for notification boxes
$(function() {
	$('#ephemeralMsg').delay(500).fadeOut(4000);
});

/* check if the value of element is not empty */
function isNotEmpty(id) {
	var elem = $('#' + id);
	if (elem) {
		var v = elem.val();
		if (v.replace(/\s+/g, ''))
			return true;
	}
	return false;
}

//  Creating our button in JS for smaller screens
$(function() {
	$('#menu').prepend('<button type="button" id="menutoggle" class="navtoogle" aria-hidden="true"><span aria-hidden="true" class="fa fa-lg fa-2x fa-bars"></span> [%|loc%]Menu[%END%]</button>');
	
	//  Toggle the class on click to show / hide the menu
	$('#menutoggle').on('click', function() {
		$(this).addClass('active');
	});
	
	// http://tympanus.net/codrops/2013/05/08/responsive-retina-ready-menu/comment-page-2/#comment-438918
	$(document).on('click', function(event) {
		var button = $('#menutoggle');
		if(event.target !== button[0] && button.is(':visible')) button.removeClass('active');
	});
});

/* Top button. */
$(function() {
    var scrollTopInner = $('<span class="scroll-top-inner">' +
        '<i class="fa fa-2x fa-arrow-circle-up"></i></span>');
    $('.scroll-top-wrapper').append(scrollTopInner);

    $(document).on('scroll', function(){
        if ($(window).scrollTop() > 100) {
            $('.scroll-top-wrapper').addClass('show');
        } else {
            $('.scroll-top-wrapper').removeClass('show');
        }
    });

    $('.scroll-top-wrapper').on('click', function(){
        $('html, body')
            .animate({scrollTop: $('body').offset().top}, 500, 'linear');
    });
});

/* Correction of disapeared top-bar-dropdown menu on input lost focus. */
$(function() {
    $('#login-dropdown').removeClass('not-click').on('mouseover',
    function(){
        $(this).addClass('hover');
    }).on('mouseout',
    function(e){
        if (e.relatedTarget
            && !$('#login-dropdown').has(e.relatedTarget).length) {
            if ($(e.target).is(':input'))
                $(e.target).blur();

            $(this).removeClass('hover');
        }
    });
});

