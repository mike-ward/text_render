#ifndef VGLYPH_OBJC_HELPERS_H
#define VGLYPH_OBJC_HELPERS_H

#include <Foundation/Foundation.h>
#include <AppKit/AppKit.h>
#include <objc/message.h>
#include <objc/runtime.h>

#ifdef __cplusplus
extern "C" {
#endif

// Use void* to avoid type conflicts/ARC issues
typedef void *V_ID;
typedef void *V_SEL;

typedef V_ID (*FN_MSG_SEND)(V_ID, V_SEL, ...);
typedef V_ID (*FN_MSG_SEND_STR)(V_ID, V_SEL, const char *);
typedef NSRect (*FN_MSG_SEND_NSRECT)(V_ID, V_SEL, ...);
typedef void (*FN_MSG_SEND_SETFRAME)(V_ID, V_SEL, NSRect, ...);
typedef void (*FN_MSG_SEND_VOID_ID)(V_ID, V_SEL, V_ID);

// Wrappers to handle ARC casting for V (voidptr)
static inline V_ID v_objc_getClass(const char *name) {
  return (__bridge void *)objc_getClass(name);
}

static inline V_SEL v_sel_registerName(const char *name) {
  return sel_registerName(name);
}

static inline V_ID v_msgSend(V_ID obj, V_SEL sel, V_ID arg1) {
  // Basic 1-arg wrapper
  return ((FN_MSG_SEND)objc_msgSend)(obj, sel, arg1);
}

static inline V_ID v_msgSend_0(V_ID obj, V_SEL sel) {
  return ((FN_MSG_SEND)objc_msgSend)(obj, sel);
}

static inline V_ID v_msgSend_str(V_ID obj, V_SEL sel, const char *str) {
  return ((FN_MSG_SEND_STR)objc_msgSend)(obj, sel, str);
}

static inline NSRect v_msgSend_nsrect(V_ID obj, V_SEL sel) {
  return ((FN_MSG_SEND_NSRECT)objc_msgSend)(obj, sel);
}

static inline void v_msgSend_setFrame(V_ID obj, V_SEL sel, NSRect rect) {
  ((FN_MSG_SEND_SETFRAME)objc_msgSend)(obj, sel, rect);
}

static inline void v_msgSend_void_id(V_ID obj, V_SEL sel, V_ID arg1) {
  ((FN_MSG_SEND_VOID_ID)objc_msgSend)(obj, sel, arg1);
}

static inline V_ID v_msgSend_array(V_ID obj, V_SEL sel, V_ID arr) {
  return ((FN_MSG_SEND)objc_msgSend)(obj, sel, arr);
}

// Wrapper for NSAccessibilityPostNotification to handle ARC bridging
static inline void v_NSAccessibilityPostNotification(V_ID element, V_ID notification) {
  NSAccessibilityPostNotification((__bridge id)element, (__bridge id)notification);
}

static inline V_ID v_NSValue_valueWithRange(NSRange range) {
  return (__bridge void *)[NSValue valueWithRange:range];
}

// Wrapper for VoiceOver announcements
// Posts NSAccessibilityAnnouncementRequestedNotification with the given message
static inline void v_NSAccessibilityAnnounce(const char *message) {
  if (message == NULL || message[0] == '\0') return;

  NSString *announcement = [NSString stringWithUTF8String:message];
  NSDictionary *userInfo = @{
    NSAccessibilityAnnouncementKey: announcement,
    NSAccessibilityPriorityKey: @(NSAccessibilityPriorityHigh)
  };

  // Post to the shared application (nil element = app-level announcement)
  NSAccessibilityPostNotificationWithUserInfo(
    [NSApplication sharedApplication],
    NSAccessibilityAnnouncementRequestedNotification,
    userInfo
  );
}

#ifdef __cplusplus
}
#endif

#endif
