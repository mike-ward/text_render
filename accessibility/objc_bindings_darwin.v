module accessibility

// objc_bindings.v provides low-level bindings to the Objective-C runtime.
// This is required to implement the NSAccessibility protocol dynamically.

#flag macos -framework Foundation
#flag macos -framework Cocoa
#flag -I @VMODROOT/accessibility

#include "objc_helpers.h"

// ObjC Types
pub type Class = voidptr
pub type SEL = voidptr
pub type Id = voidptr
pub type IMP = voidptr

// ObjC Functions
// ObjC Functions
fn C.v_objc_getClass(name &char) Class
fn C.v_sel_registerName(name &char) SEL
fn C.object_getClass(obj Id) Class
fn C.class_getName(cls Class) &char
fn C.class_addMethod(cls Class, name SEL, imp IMP, types &char) bool
fn C.class_replaceMethod(cls Class, name SEL, imp IMP, types &char) IMP
fn C.method_exchangeImplementations(m1 voidptr, m2 voidptr)
fn C.class_getInstanceMethod(cls Class, name SEL) voidptr

// Wrapped definitions matching the inline functions
fn C.v_msgSend(self Id, op SEL, arg1 voidptr) Id
fn C.v_msgSend_0(self Id, op SEL) Id
fn C.v_msgSend_fret(self Id, op SEL, ...voidptr) f64
fn C.v_msgSend_nsrect(self Id, op SEL) C.NSRect
fn C.v_msgSend_setFrame(self Id, op SEL, rect C.NSRect)
fn C.v_msgSend_void_id(self Id, op SEL, arg1 voidptr)
fn C.v_msgSend_str(self Id, op SEL, str &char) Id

// objc_get_class returns the Objective-C class object for the named class.
pub fn objc_get_class(name string) Class {
	return C.v_objc_getClass(name.str)
}

// sel_register_name registers a selector name and returns its SEL handle.
pub fn sel_register_name(name string) SEL {
	return C.v_sel_registerName(name.str)
}

// Structs
@[typedef]
pub struct C.CGPoint {
pub mut:
	x f64
	y f64
}

@[typedef]
pub struct C.CGSize {
pub mut:
	width  f64
	height f64
}

@[typedef]
pub struct C.NSRect {
pub mut:
	origin C.CGPoint
	size   C.CGSize
}

@[typedef]
pub struct C.NSRange {
pub mut:
	location u64
	length   u64
}

// make_ns_rect creates an NSRect from float coordinates.
pub fn make_ns_rect(x f32, y f32, w f32, h f32) C.NSRect {
	return C.NSRect{
		origin: C.CGPoint{
			x: f64(x)
			y: f64(y)
		}
		size:   C.CGSize{
			width:  f64(w)
			height: f64(h)
		}
	}
}

// NSString Helper
pub fn ns_string(s string) Id {
	cls := C.v_objc_getClass(c'NSString')
	sel := C.v_sel_registerName(c'stringWithUTF8String:')
	return C.v_msgSend_str(cls, sel, s.str)
}

// NSArray Helper
// We use NSMutableArray for simpler construction
pub fn ns_mutable_array_new() Id {
	cls := C.v_objc_getClass(c'NSMutableArray')
	alloc := C.v_msgSend_0(cls, C.v_sel_registerName(c'alloc'))
	return C.v_msgSend_0(alloc, C.v_sel_registerName(c'init'))
}

// ns_array_add_object appends an object to an NSMutableArray.
pub fn ns_array_add_object(arr Id, obj Id) {
	C.v_msgSend(arr, C.v_sel_registerName(c'addObject:'), obj)
}

// NSRange Helper
pub fn make_ns_range(location int, length int) C.NSRange {
	return C.NSRange{
		location: u64(location)
		length:   u64(length)
	}
}

// NSAccessibility Notification Functions (uses wrapper for ARC bridging)
fn C.v_NSAccessibilityPostNotification(element Id, notification Id)
fn C.v_NSAccessibilityAnnounce(message &char)
fn C.v_NSValue_valueWithRange(range C.NSRange) Id

// post_accessibility_notification posts a named notification for an element.
pub fn post_accessibility_notification(element Id, notification string) {
	notif_ns := ns_string(notification)
	C.v_NSAccessibilityPostNotification(element, notif_ns)
}

// ns_value_with_range wraps an NSRange in an NSValue.
pub fn ns_value_with_range(range C.NSRange) Id {
	return C.v_NSValue_valueWithRange(range)
}

// announce_to_voiceover posts an announcement to VoiceOver.
// Uses NSAccessibilityAnnouncementRequestedNotification.
pub fn announce_to_voiceover(message string) {
	if message.len == 0 {
		return
	}
	C.v_NSAccessibilityAnnounce(message.str)
}
