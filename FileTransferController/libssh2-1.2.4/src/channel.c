/* Copyright (c) 2004-2007 Sara Golemon <sarag@libssh2.org>
 * Copyright (c) 2008-2009 by Daniel Stenberg
 *
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms,
 * with or without modification, are permitted provided
 * that the following conditions are met:
 *
 *   Redistributions of source code must retain the above
 *   copyright notice, this list of conditions and the
 *   following disclaimer.
 *
 *   Redistributions in binary form must reproduce the above
 *   copyright notice, this list of conditions and the following
 *   disclaimer in the documentation and/or other materials
 *   provided with the distribution.
 *
 *   Neither the name of the copyright holder nor the names
 *   of any other contributors may be used to endorse or
 *   promote products derived from this software without
 *   specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
 * CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
 * USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY
 * OF SUCH DAMAGE.
 */

#include "libssh2_priv.h"
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#include <fcntl.h>
#ifdef HAVE_INTTYPES_H
#include <inttypes.h>
#endif
#include <assert.h>

#include "channel.h"
#include "transport.h"

/*
 *  _libssh2_channel_nextid
 *
 * Determine the next channel ID we can use at our end
 */
unsigned long
_libssh2_channel_nextid(LIBSSH2_SESSION * session)
{
    unsigned long id = session->next_channel;
    LIBSSH2_CHANNEL *channel;

    channel = _libssh2_list_first(&session->channels);

    while (channel) {
        if (channel->local.id > id) {
            id = channel->local.id;
        }
        channel = _libssh2_list_next(&channel->node);
    }

    /* This is a shortcut to avoid waiting for close packets on channels we've
     * forgotten about, This *could* be a problem if we request and close 4
     * billion or so channels in too rapid succession for the remote end to
     * respond, but the worst case scenario is that some data meant for
     * another channel Gets picked up by the new one.... Pretty unlikely all
     * told...
     */
    session->next_channel = id + 1;
    _libssh2_debug(session, LIBSSH2_TRACE_CONN, "Allocated new channel ID#%lu",
                   id);
    return id;
}

/*
 * _libssh2_channel_locate
 *
 * Locate a channel pointer by number
 */
LIBSSH2_CHANNEL *
_libssh2_channel_locate(LIBSSH2_SESSION *session, unsigned long channel_id)
{
    LIBSSH2_CHANNEL *channel;
    LIBSSH2_LISTENER *l;

    for(channel = _libssh2_list_first(&session->channels);
        channel;
        channel = _libssh2_list_next(&channel->node)) {
        if (channel->local.id == channel_id)
            return channel;
    }

    /* We didn't find the channel in the session, let's then check its
       listeners since each listener may have its own set of pending channels
    */
    for(l = _libssh2_list_first(&session->listeners); l;
        l = _libssh2_list_next(&l->node)) {
        for(channel = _libssh2_list_first(&l->queue);
            channel;
            channel = _libssh2_list_next(&channel->node)) {
            if (channel->local.id == channel_id)
                return channel;
        }
    }

    return NULL;
}

/*
 * _libssh2_channel_open
 *
 * Establish a generic session channel
 */
LIBSSH2_CHANNEL *
_libssh2_channel_open(LIBSSH2_SESSION * session, const char *channel_type,
                      unsigned int channel_type_len,
                      unsigned int window_size, unsigned int packet_size,
                      const char *message, unsigned int message_len)
{
    static const unsigned char reply_codes[3] = {
        SSH_MSG_CHANNEL_OPEN_CONFIRMATION,
        SSH_MSG_CHANNEL_OPEN_FAILURE,
        0
    };
    unsigned char *s;
    int rc;

    if (session->open_state == libssh2_NB_state_idle) {
        session->open_channel = NULL;
        session->open_packet = NULL;
        session->open_data = NULL;
        /* 17 = packet_type(1) + channel_type_len(4) + sender_channel(4) +
         * window_size(4) + packet_size(4) */
        session->open_packet_len = channel_type_len + message_len + 17;
        session->open_local_channel = _libssh2_channel_nextid(session);

        /* Zero the whole thing out */
        memset(&session->open_packet_requirev_state, 0,
               sizeof(session->open_packet_requirev_state));

        _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                       "Opening Channel - win %d pack %d", window_size,
                       packet_size);
        session->open_channel =
            LIBSSH2_ALLOC(session, sizeof(LIBSSH2_CHANNEL));
        if (!session->open_channel) {
            libssh2_error(session, LIBSSH2_ERROR_ALLOC,
                          "Unable to allocate space for channel data", 0);
            return NULL;
        }
        memset(session->open_channel, 0, sizeof(LIBSSH2_CHANNEL));

        session->open_channel->channel_type_len = channel_type_len;
        session->open_channel->channel_type =
            LIBSSH2_ALLOC(session, channel_type_len);
        if (!session->open_channel->channel_type) {
            libssh2_error(session, LIBSSH2_ERROR_ALLOC,
                          "Failed allocating memory for channel type name", 0);
            LIBSSH2_FREE(session, session->open_channel);
            session->open_channel = NULL;
            return NULL;
        }
        memcpy(session->open_channel->channel_type, channel_type,
               channel_type_len);

        /* REMEMBER: local as in locally sourced */
        session->open_channel->local.id = session->open_local_channel;
        session->open_channel->remote.window_size = window_size;
        session->open_channel->remote.window_size_initial = window_size;
        session->open_channel->remote.packet_size = packet_size;
        session->open_channel->session = session;

        _libssh2_list_add(&session->channels,
                          &session->open_channel->node);

        s = session->open_packet =
            LIBSSH2_ALLOC(session, session->open_packet_len);
        if (!session->open_packet) {
            libssh2_error(session, LIBSSH2_ERROR_ALLOC,
                          "Unable to allocate temporary space for packet", 0);
            goto channel_error;
        }
        *(s++) = SSH_MSG_CHANNEL_OPEN;
        _libssh2_htonu32(s, channel_type_len);
        s += 4;

        memcpy(s, channel_type, channel_type_len);
        s += channel_type_len;

        _libssh2_htonu32(s, session->open_local_channel);
        s += 4;

        _libssh2_htonu32(s, window_size);
        s += 4;

        _libssh2_htonu32(s, packet_size);
        s += 4;

        if (message && message_len) {
            memcpy(s, message, message_len);
            s += message_len;
        }

        session->open_state = libssh2_NB_state_created;
    }

    if (session->open_state == libssh2_NB_state_created) {
        rc = _libssh2_transport_write(session, session->open_packet,
                                      session->open_packet_len);
        if (rc == PACKET_EAGAIN) {
            libssh2_error(session, LIBSSH2_ERROR_EAGAIN,
                          "Would block sending channel-open request", 0);
            return NULL;
        } else if (rc) {
            libssh2_error(session, LIBSSH2_ERROR_SOCKET_SEND,
                          "Unable to send channel-open request", 0);
            goto channel_error;
        }

        session->open_state = libssh2_NB_state_sent;
    }

    if (session->open_state == libssh2_NB_state_sent) {
        rc = _libssh2_packet_requirev(session, reply_codes,
                                      &session->open_data,
                                      &session->open_data_len, 1,
                                      session->open_packet + 5 +
                                      channel_type_len, 4,
                                      &session->open_packet_requirev_state);
        if (rc == PACKET_EAGAIN) {
            libssh2_error(session, LIBSSH2_ERROR_EAGAIN, "Would block", 0);
            return NULL;
        } else if (rc) {
            goto channel_error;
        }

        if (session->open_data[0] == SSH_MSG_CHANNEL_OPEN_CONFIRMATION) {
            session->open_channel->remote.id =
                _libssh2_ntohu32(session->open_data + 5);
            session->open_channel->local.window_size =
                _libssh2_ntohu32(session->open_data + 9);
            session->open_channel->local.window_size_initial =
                _libssh2_ntohu32(session->open_data + 9);
            session->open_channel->local.packet_size =
                _libssh2_ntohu32(session->open_data + 13);
            _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                           "Connection Established - ID: %lu/%lu win: %lu/%lu"
                           " pack: %lu/%lu",
                           session->open_channel->local.id,
                           session->open_channel->remote.id,
                           session->open_channel->local.window_size,
                           session->open_channel->remote.window_size,
                           session->open_channel->local.packet_size,
                           session->open_channel->remote.packet_size);
            LIBSSH2_FREE(session, session->open_packet);
            session->open_packet = NULL;
            LIBSSH2_FREE(session, session->open_data);
            session->open_data = NULL;

            session->open_state = libssh2_NB_state_idle;
            return session->open_channel;
        }

        if (session->open_data[0] == SSH_MSG_CHANNEL_OPEN_FAILURE) {
            libssh2_error(session, LIBSSH2_ERROR_CHANNEL_FAILURE,
                          "Channel open failure", 0);
        }
    }

  channel_error:

    if (session->open_data) {
        LIBSSH2_FREE(session, session->open_data);
        session->open_data = NULL;
    }
    if (session->open_packet) {
        LIBSSH2_FREE(session, session->open_packet);
        session->open_packet = NULL;
    }
    if (session->open_channel) {
        unsigned char channel_id[4];
        LIBSSH2_FREE(session, session->open_channel->channel_type);

        _libssh2_list_remove(&session->open_channel->node);

        /* Clear out packets meant for this channel */
        _libssh2_htonu32(channel_id, session->open_channel->local.id);
        while ((_libssh2_packet_ask(session, SSH_MSG_CHANNEL_DATA,
                                    &session->open_data,
                                    &session->open_data_len, 1,
                                    channel_id, 4) >= 0)
               ||
               (_libssh2_packet_ask(session, SSH_MSG_CHANNEL_EXTENDED_DATA,
                                    &session->open_data,
                                    &session->open_data_len, 1,
                                    channel_id, 4) >= 0)) {
            LIBSSH2_FREE(session, session->open_data);
            session->open_data = NULL;
        }

        /* Free any state variables still holding data */
        if (session->open_channel->write_packet) {
            LIBSSH2_FREE(session, session->open_channel->write_packet);
            session->open_channel->write_packet = NULL;
        }

        LIBSSH2_FREE(session, session->open_channel);
        session->open_channel = NULL;
    }

    session->open_state = libssh2_NB_state_idle;
    return NULL;
}

/*
 * libssh2_channel_open_ex
 *
 * Establish a generic session channel
 */
LIBSSH2_API LIBSSH2_CHANNEL *
libssh2_channel_open_ex(LIBSSH2_SESSION *session, const char *type,
                        unsigned int type_len,
                        unsigned int window_size, unsigned int packet_size,
                        const char *msg, unsigned int msg_len)
{
    LIBSSH2_CHANNEL *ptr;
    BLOCK_ADJUST_ERRNO(ptr, session,
                       _libssh2_channel_open(session, type, type_len,
                                             window_size, packet_size,
                                             msg, msg_len));
    return ptr;
}

/*
 * libssh2_channel_direct_tcpip_ex
 *
 * Tunnel TCP/IP connect through the SSH session to direct host/port
 */
static LIBSSH2_CHANNEL *
channel_direct_tcpip(LIBSSH2_SESSION * session, const char *host,
                     int port, const char *shost, int sport)
{
    LIBSSH2_CHANNEL *channel;
    unsigned char *s;

    if (session->direct_state == libssh2_NB_state_idle) {
        session->direct_host_len = strlen(host);
        session->direct_shost_len = strlen(shost);
        /* host_len(4) + port(4) + shost_len(4) + sport(4) */
        session->direct_message_len =
            session->direct_host_len + session->direct_shost_len + 16;

        _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                       "Requesting direct-tcpip session to from %s:%d to %s:%d",
                       shost, sport, host, port);

        s = session->direct_message =
            LIBSSH2_ALLOC(session, session->direct_message_len);
        if (!session->direct_message) {
            libssh2_error(session, LIBSSH2_ERROR_ALLOC,
                          "Unable to allocate memory for direct-tcpip connection",
                          0);
            return NULL;
        }
        _libssh2_htonu32(s, session->direct_host_len);
        s += 4;
        memcpy(s, host, session->direct_host_len);
        s += session->direct_host_len;
        _libssh2_htonu32(s, port);
        s += 4;

        _libssh2_htonu32(s, session->direct_shost_len);
        s += 4;
        memcpy(s, shost, session->direct_shost_len);
        s += session->direct_shost_len;
        _libssh2_htonu32(s, sport);
        s += 4;
    }

    channel =
        libssh2_channel_open_ex(session, "direct-tcpip",
                                sizeof("direct-tcpip") - 1,
                                LIBSSH2_CHANNEL_WINDOW_DEFAULT,
                                LIBSSH2_CHANNEL_PACKET_DEFAULT,
                                (char *) session->direct_message,
                                session->direct_message_len);

    /* by default we set (keep?) idle state... */
    session->direct_state = libssh2_NB_state_idle;

    if (!channel &&
        libssh2_session_last_errno(session) == LIBSSH2_ERROR_EAGAIN) {
        /* The error code is still set to LIBSSH2_ERROR_EAGAIN, set our state
           to created to avoid re-creating the package on next invoke */
        session->direct_state = libssh2_NB_state_created;
        return NULL;
    }

    LIBSSH2_FREE(session, session->direct_message);
    session->direct_message = NULL;

    return channel;
}

/*
 * libssh2_channel_direct_tcpip_ex
 *
 * Tunnel TCP/IP connect through the SSH session to direct host/port
 */
LIBSSH2_API LIBSSH2_CHANNEL *
libssh2_channel_direct_tcpip_ex(LIBSSH2_SESSION * session, const char *host,
                                int port, const char *shost, int sport)
{
    LIBSSH2_CHANNEL *ptr;
    BLOCK_ADJUST_ERRNO(ptr, session,
                       channel_direct_tcpip(session, host, port, shost, sport));
    return ptr;
}

/*
 * channel_forward_listen
 *
 * Bind a port on the remote host and listen for connections
 */
static LIBSSH2_LISTENER *
channel_forward_listen(LIBSSH2_SESSION * session, const char *host,
                       int port, int *bound_port, int queue_maxsize)
{
    unsigned char *s, *data;
    static const unsigned char reply_codes[3] =
        { SSH_MSG_REQUEST_SUCCESS, SSH_MSG_REQUEST_FAILURE, 0 };
    unsigned long data_len;
    int rc;

    if (session->fwdLstn_state == libssh2_NB_state_idle) {
        session->fwdLstn_host_len =
            (host ? strlen(host) : (sizeof("0.0.0.0") - 1));
        /* 14 = packet_type(1) + request_len(4) + want_replay(1) + host_len(4)
           + port(4) */
        session->fwdLstn_packet_len =
            session->fwdLstn_host_len + (sizeof("tcpip-forward") - 1) + 14;

        /* Zero the whole thing out */
        memset(&session->fwdLstn_packet_requirev_state, 0,
               sizeof(session->fwdLstn_packet_requirev_state));

        _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                       "Requesting tcpip-forward session for %s:%d", host,
                       port);

        s = session->fwdLstn_packet =
            LIBSSH2_ALLOC(session, session->fwdLstn_packet_len);
        if (!session->fwdLstn_packet) {
            libssh2_error(session, LIBSSH2_ERROR_ALLOC,
                          "Unable to allocate memeory for setenv packet", 0);
            return NULL;
        }

        *(s++) = SSH_MSG_GLOBAL_REQUEST;
        _libssh2_htonu32(s, sizeof("tcpip-forward") - 1);
        s += 4;
        memcpy(s, "tcpip-forward", sizeof("tcpip-forward") - 1);
        s += sizeof("tcpip-forward") - 1;
        *(s++) = 0x01;          /* want_reply */

        _libssh2_htonu32(s, session->fwdLstn_host_len);
        s += 4;
        memcpy(s, host ? host : "0.0.0.0", session->fwdLstn_host_len);
        s += session->fwdLstn_host_len;
        _libssh2_htonu32(s, port);
        s += 4;

        session->fwdLstn_state = libssh2_NB_state_created;
    }

    if (session->fwdLstn_state == libssh2_NB_state_created) {
        rc = _libssh2_transport_write(session, session->fwdLstn_packet,
                                   session->fwdLstn_packet_len);
        if (rc == PACKET_EAGAIN) {
            libssh2_error(session, LIBSSH2_ERROR_EAGAIN,
                          "Would block sending global-request packet for "
                          "forward listen request",
                          0);
            return NULL;
        } else if (rc) {
            libssh2_error(session, LIBSSH2_ERROR_SOCKET_SEND,
                          "Unable to send global-request packet for forward "
                          "listen request",
                          0);
            LIBSSH2_FREE(session, session->fwdLstn_packet);
            session->fwdLstn_packet = NULL;
            session->fwdLstn_state = libssh2_NB_state_idle;
            return NULL;
        }
        LIBSSH2_FREE(session, session->fwdLstn_packet);
        session->fwdLstn_packet = NULL;

        session->fwdLstn_state = libssh2_NB_state_sent;
    }

    if (session->fwdLstn_state == libssh2_NB_state_sent) {
        rc = _libssh2_packet_requirev(session, reply_codes, &data, &data_len,
                                      0, NULL, 0,
                                      &session->fwdLstn_packet_requirev_state);
        if (rc == PACKET_EAGAIN) {
            libssh2_error(session, LIBSSH2_ERROR_EAGAIN, "Would block", 0);
            return NULL;
        } else if (rc) {
            libssh2_error(session, LIBSSH2_ERROR_PROTO, "Unknown", 0);
            session->fwdLstn_state = libssh2_NB_state_idle;
            return NULL;
        }

        if (data[0] == SSH_MSG_REQUEST_SUCCESS) {
            LIBSSH2_LISTENER *listener;

            listener = LIBSSH2_ALLOC(session, sizeof(LIBSSH2_LISTENER));
            if (!listener) {
                libssh2_error(session, LIBSSH2_ERROR_ALLOC,
                              "Unable to allocate memory for listener queue",
                              0);
                LIBSSH2_FREE(session, data);
                session->fwdLstn_state = libssh2_NB_state_idle;
                return NULL;
            }
            memset(listener, 0, sizeof(LIBSSH2_LISTENER));
            listener->session = session;
            listener->host =
                LIBSSH2_ALLOC(session, session->fwdLstn_host_len + 1);
            if (!listener->host) {
                libssh2_error(session, LIBSSH2_ERROR_ALLOC,
                              "Unable to allocate memory for listener queue",
                              0);
                LIBSSH2_FREE(session, listener);
                LIBSSH2_FREE(session, data);
                session->fwdLstn_state = libssh2_NB_state_idle;
                return NULL;
            }
            memcpy(listener->host, host ? host : "0.0.0.0",
                   session->fwdLstn_host_len);
            listener->host[session->fwdLstn_host_len] = 0;
            if (data_len >= 5 && !port) {
                listener->port = _libssh2_ntohu32(data + 1);
                _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                               "Dynamic tcpip-forward port allocated: %d",
                               listener->port);
            } else {
                listener->port = port;
            }

            listener->queue_size = 0;
            listener->queue_maxsize = queue_maxsize;

            /* append this to the parent's list of listeners */
            _libssh2_list_add(&session->listeners, &listener->node);

            if (bound_port) {
                *bound_port = listener->port;
            }

            LIBSSH2_FREE(session, data);
            session->fwdLstn_state = libssh2_NB_state_idle;
            return listener;
        }

        if (data[0] == SSH_MSG_REQUEST_FAILURE) {
            LIBSSH2_FREE(session, data);
            libssh2_error(session, LIBSSH2_ERROR_REQUEST_DENIED,
                          "Unable to complete request for forward-listen", 0);
            session->fwdLstn_state = libssh2_NB_state_idle;
            return NULL;
        }
    }

    session->fwdLstn_state = libssh2_NB_state_idle;

    return NULL;
}

/*
 * libssh2_channel_forward_listen_ex
 *
 * Bind a port on the remote host and listen for connections
 */
LIBSSH2_API LIBSSH2_LISTENER *
libssh2_channel_forward_listen_ex(LIBSSH2_SESSION *session, const char *host,
                                  int port, int *bound_port, int queue_maxsize)
{
    LIBSSH2_LISTENER *ptr;
    BLOCK_ADJUST_ERRNO(ptr, session,
                       channel_forward_listen(session, host, port, bound_port,
                                              queue_maxsize));
    return ptr;
}

/*
 * channel_forward_cancel
 *
 * Stop listening on a remote port and free the listener
 * Toss out any pending (un-accept()ed) connections
 *
 * Return 0 on success, PACKET_EAGAIN if would block, -1 on error
 */
static int channel_forward_cancel(LIBSSH2_LISTENER *listener)
{
    LIBSSH2_SESSION *session = listener->session;
    LIBSSH2_CHANNEL *queued;
    unsigned char *packet, *s;
    unsigned long host_len = strlen(listener->host);
    /* 14 = packet_type(1) + request_len(4) + want_replay(1) + host_len(4) +
       port(4) */
    unsigned long packet_len =
        host_len + 14 + sizeof("cancel-tcpip-forward") - 1;
    int rc;

    if (listener->chanFwdCncl_state == libssh2_NB_state_idle) {
        _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                       "Cancelling tcpip-forward session for %s:%d",
                       listener->host, listener->port);

        s = packet = LIBSSH2_ALLOC(session, packet_len);
        if (!packet) {
            libssh2_error(session, LIBSSH2_ERROR_ALLOC,
                          "Unable to allocate memeory for setenv packet", 0);
            return LIBSSH2_ERROR_ALLOC;
        }

        *(s++) = SSH_MSG_GLOBAL_REQUEST;
        _libssh2_htonu32(s, sizeof("cancel-tcpip-forward") - 1);
        s += 4;
        memcpy(s, "cancel-tcpip-forward", sizeof("cancel-tcpip-forward") - 1);
        s += sizeof("cancel-tcpip-forward") - 1;
        *(s++) = 0x00;          /* want_reply */

        _libssh2_htonu32(s, host_len);
        s += 4;
        memcpy(s, listener->host, host_len);
        s += host_len;
        _libssh2_htonu32(s, listener->port);
        s += 4;

        listener->chanFwdCncl_state = libssh2_NB_state_created;
    } else {
        packet = listener->chanFwdCncl_data;
    }

    if (listener->chanFwdCncl_state == libssh2_NB_state_created) {
        rc = _libssh2_transport_write(session, packet, packet_len);
        if (rc == PACKET_EAGAIN) {
            listener->chanFwdCncl_data = packet;
            return rc;
        }
        else if (rc) {
            libssh2_error(session, LIBSSH2_ERROR_SOCKET_SEND,
                          "Unable to send global-request packet for forward "
                          "listen request",
                          0);
            LIBSSH2_FREE(session, packet);
            listener->chanFwdCncl_state = libssh2_NB_state_idle;
            return LIBSSH2_ERROR_SOCKET_SEND;
        }
        LIBSSH2_FREE(session, packet);

        listener->chanFwdCncl_state = libssh2_NB_state_sent;
    }

    queued = _libssh2_list_first(&listener->queue);
    while (queued) {
        LIBSSH2_CHANNEL *next = _libssh2_list_next(&queued->node);

        rc = libssh2_channel_free(queued);
        if (rc == PACKET_EAGAIN) {
            return rc;
        }
        queued = next;
    }
    LIBSSH2_FREE(session, listener->host);

    /* remove this entry from the parent's list of listeners */
    _libssh2_list_remove(&listener->node);

    LIBSSH2_FREE(session, listener);

    listener->chanFwdCncl_state = libssh2_NB_state_idle;

    return 0;
}

/*
 * libssh2_channel_forward_cancel
 *
 * Stop listening on a remote port and free the listener
 * Toss out any pending (un-accept()ed) connections
 *
 * Return 0 on success, PACKET_EAGAIN if would block, -1 on error
 */
LIBSSH2_API int
libssh2_channel_forward_cancel(LIBSSH2_LISTENER *listener)
{
    int rc;
    BLOCK_ADJUST(rc, listener->session, channel_forward_cancel(listener));
    return rc;
}

/*
 * channel_forward_accept
 *
 * Accept a connection
 */
static LIBSSH2_CHANNEL *
channel_forward_accept(LIBSSH2_LISTENER *listener)
{
    int rc;

    do {
        rc = _libssh2_transport_read(listener->session);
    } while (rc > 0);

    if (_libssh2_list_first(&listener->queue)) {
        LIBSSH2_CHANNEL *channel = _libssh2_list_first(&listener->queue);

        /* detach channel from listener's queue */
        _libssh2_list_remove(&channel->node);

        listener->queue_size--;

        /* add channel to session's channel list */
        _libssh2_list_add(&channel->session->channels, &channel->node);

        return channel;
    }

    if (rc == PACKET_EAGAIN) {
        libssh2_error(listener->session, LIBSSH2_ERROR_EAGAIN,
                      "Would block waiting for packet", 0);
    }
    else
        libssh2_error(listener->session, LIBSSH2_ERROR_CHANNEL_UNKNOWN,
                      "Channel not found", 0);
    return NULL;
}

/*
 * libssh2_channel_forward_accept
 *
 * Accept a connection
 */
LIBSSH2_API LIBSSH2_CHANNEL *
libssh2_channel_forward_accept(LIBSSH2_LISTENER *listener)
{
    LIBSSH2_CHANNEL *ptr;
    BLOCK_ADJUST_ERRNO(ptr, listener->session,
                       channel_forward_accept(listener));
    return ptr;

}

/*
 * channel_setenv
 *
 * Set an environment variable prior to requesting a shell/program/subsystem
 */
static int channel_setenv(LIBSSH2_CHANNEL *channel,
                          const char *varname, unsigned int varname_len,
                          const char *value, unsigned int value_len)
{
    LIBSSH2_SESSION *session = channel->session;
    unsigned char *s, *data;
    static const unsigned char reply_codes[3] =
        { SSH_MSG_CHANNEL_SUCCESS, SSH_MSG_CHANNEL_FAILURE, 0 };
    unsigned long data_len;
    int rc;

    if (channel->setenv_state == libssh2_NB_state_idle) {
        /* 21 = packet_type(1) + channel_id(4) + request_len(4) +
         * request(3)"env" + want_reply(1) + varname_len(4) + value_len(4) */
        channel->setenv_packet_len = varname_len + value_len + 21;

        /* Zero the whole thing out */
        memset(&channel->setenv_packet_requirev_state, 0,
               sizeof(channel->setenv_packet_requirev_state));

        _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                       "Setting remote environment variable: %s=%s on "
                       "channel %lu/%lu",
                       varname, value, channel->local.id, channel->remote.id);

        s = channel->setenv_packet =
            LIBSSH2_ALLOC(session, channel->setenv_packet_len);
        if (!channel->setenv_packet) {
            libssh2_error(session, LIBSSH2_ERROR_ALLOC,
                          "Unable to allocate memeory for setenv packet", 0);
            return LIBSSH2_ERROR_ALLOC;
        }

        *(s++) = SSH_MSG_CHANNEL_REQUEST;
        _libssh2_htonu32(s, channel->remote.id);
        s += 4;
        _libssh2_htonu32(s, sizeof("env") - 1);
        s += 4;
        memcpy(s, "env", sizeof("env") - 1);
        s += sizeof("env") - 1;

        *(s++) = 0x01;

        _libssh2_htonu32(s, varname_len);
        s += 4;
        memcpy(s, varname, varname_len);
        s += varname_len;

        _libssh2_htonu32(s, value_len);
        s += 4;
        memcpy(s, value, value_len);
        s += value_len;

        channel->setenv_state = libssh2_NB_state_created;
    }

    if (channel->setenv_state == libssh2_NB_state_created) {
        rc = _libssh2_transport_write(session, channel->setenv_packet,
                                  channel->setenv_packet_len);
        if (rc == PACKET_EAGAIN) {
            return rc;
        } else if (rc) {
            libssh2_error(session, LIBSSH2_ERROR_SOCKET_SEND,
                          "Unable to send channel-request packet for "
                          "setenv request",
                          0);
            LIBSSH2_FREE(session, channel->setenv_packet);
            channel->setenv_packet = NULL;
            channel->setenv_state = libssh2_NB_state_idle;
            return LIBSSH2_ERROR_SOCKET_SEND;
        }
        LIBSSH2_FREE(session, channel->setenv_packet);
        channel->setenv_packet = NULL;

        _libssh2_htonu32(channel->setenv_local_channel, channel->local.id);

        channel->setenv_state = libssh2_NB_state_sent;
    }

    if (channel->setenv_state == libssh2_NB_state_sent) {
        rc = _libssh2_packet_requirev(session, reply_codes, &data, &data_len,
                                      1, channel->setenv_local_channel, 4,
                                      &channel->
                                      setenv_packet_requirev_state);
        if (rc == PACKET_EAGAIN) {
            return rc;
        }
        if (rc) {
            channel->setenv_state = libssh2_NB_state_idle;
            return rc;
        }

        if (data[0] == SSH_MSG_CHANNEL_SUCCESS) {
            LIBSSH2_FREE(session, data);
            channel->setenv_state = libssh2_NB_state_idle;
            return 0;
        }

        LIBSSH2_FREE(session, data);
    }

    libssh2_error(session, LIBSSH2_ERROR_CHANNEL_REQUEST_DENIED,
                  "Unable to complete request for channel-setenv", 0);
    channel->setenv_state = libssh2_NB_state_idle;
    return LIBSSH2_ERROR_CHANNEL_REQUEST_DENIED;
}

/*
 * libssh2_channel_setenv_ex
 *
 * Set an environment variable prior to requesting a shell/program/subsystem
 */
LIBSSH2_API int
libssh2_channel_setenv_ex(LIBSSH2_CHANNEL *channel,
                          const char *varname, unsigned int varname_len,
                          const char *value, unsigned int value_len)
{
    int rc;
    BLOCK_ADJUST(rc, channel->session,
                 channel_setenv(channel, varname, varname_len,
                                value, value_len));
    return rc;
}

/*
 * channel_request_pty
 * Duh... Request a PTY
 */
static int channel_request_pty(LIBSSH2_CHANNEL *channel,
                               const char *term, unsigned int term_len,
                               const char *modes, unsigned int modes_len,
                               int width, int height,
                               int width_px, int height_px)
{
    LIBSSH2_SESSION *session = channel->session;
    unsigned char *s, *data;
    static const unsigned char reply_codes[3] =
        { SSH_MSG_CHANNEL_SUCCESS, SSH_MSG_CHANNEL_FAILURE, 0 };
    unsigned long data_len;
    int rc;

    if (channel->reqPTY_state == libssh2_NB_state_idle) {
        /* 41 = packet_type(1) + channel(4) + pty_req_len(4) + "pty_req"(7) +
         * want_reply(1) + term_len(4) + width(4) + height(4) + width_px(4) +
         * height_px(4) + modes_len(4) */
        channel->reqPTY_packet_len = term_len + modes_len + 41;

        /* Zero the whole thing out */
        memset(&channel->reqPTY_packet_requirev_state, 0,
               sizeof(channel->reqPTY_packet_requirev_state));

        _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                       "Allocating tty on channel %lu/%lu", channel->local.id,
                       channel->remote.id);

        s = channel->reqPTY_packet =
            LIBSSH2_ALLOC(session, channel->reqPTY_packet_len);
        if (!channel->reqPTY_packet) {
            libssh2_error(session, LIBSSH2_ERROR_ALLOC,
                          "Unable to allocate memory for pty-request", 0);
            return -1;
        }

        *(s++) = SSH_MSG_CHANNEL_REQUEST;
        _libssh2_htonu32(s, channel->remote.id);
        s += 4;
        _libssh2_htonu32(s, sizeof("pty-req") - 1);
        s += 4;
        memcpy(s, "pty-req", sizeof("pty-req") - 1);
        s += sizeof("pty-req") - 1;

        *(s++) = 0x01;

        _libssh2_htonu32(s, term_len);
        s += 4;
        if (term) {
            memcpy(s, term, term_len);
            s += term_len;
        }

        _libssh2_htonu32(s, width);
        s += 4;
        _libssh2_htonu32(s, height);
        s += 4;
        _libssh2_htonu32(s, width_px);
        s += 4;
        _libssh2_htonu32(s, height_px);
        s += 4;

        _libssh2_htonu32(s, modes_len);
        s += 4;
        if (modes) {
            memcpy(s, modes, modes_len);
            s += modes_len;
        }

        channel->reqPTY_state = libssh2_NB_state_created;
    }

    if (channel->reqPTY_state == libssh2_NB_state_created) {
        rc = _libssh2_transport_write(session, channel->reqPTY_packet,
                                   channel->reqPTY_packet_len);
        if (rc == PACKET_EAGAIN) {
            return rc;
        } else if (rc) {
            libssh2_error(session, rc,
                          "Unable to send pty-request packet", 0);
            LIBSSH2_FREE(session, channel->reqPTY_packet);
            channel->reqPTY_packet = NULL;
            channel->reqPTY_state = libssh2_NB_state_idle;
            return rc;
        }
        LIBSSH2_FREE(session, channel->reqPTY_packet);
        channel->reqPTY_packet = NULL;

        _libssh2_htonu32(channel->reqPTY_local_channel, channel->local.id);

        channel->reqPTY_state = libssh2_NB_state_sent;
    }

    if (channel->reqPTY_state == libssh2_NB_state_sent) {
        rc = _libssh2_packet_requirev(session, reply_codes, &data, &data_len,
                                      1, channel->reqPTY_local_channel, 4,
                                      &channel->reqPTY_packet_requirev_state);
        if (rc == PACKET_EAGAIN) {
            return rc;
        } else if (rc) {
            channel->reqPTY_state = libssh2_NB_state_idle;
            return -1;
        }

        if (data[0] == SSH_MSG_CHANNEL_SUCCESS) {
            LIBSSH2_FREE(session, data);
            channel->reqPTY_state = libssh2_NB_state_idle;
            return 0;
        }
    }

    LIBSSH2_FREE(session, data);
    libssh2_error(session, LIBSSH2_ERROR_CHANNEL_REQUEST_DENIED,
                  "Unable to complete request for channel request-pty", 0);
    channel->reqPTY_state = libssh2_NB_state_idle;
    return LIBSSH2_ERROR_CHANNEL_REQUEST_DENIED;
}

/*
 * libssh2_channel_request_pty_ex
 * Duh... Request a PTY
 */
LIBSSH2_API int
libssh2_channel_request_pty_ex(LIBSSH2_CHANNEL *channel, const char *term,
                               unsigned int term_len, const char *modes,
                               unsigned int modes_len, int width, int height,
                               int width_px, int height_px)
{
    int rc;
    BLOCK_ADJUST(rc, channel->session,
                 channel_request_pty(channel, term, term_len, modes,
                                     modes_len, width, height,
                                     width_px, height_px));
    return rc;
}

static int
channel_request_pty_size(LIBSSH2_CHANNEL * channel, int width,
                         int height, int width_px, int height_px)
{
    LIBSSH2_SESSION *session = channel->session;
    unsigned char *s;
    int rc;

    if (channel->reqPTY_state == libssh2_NB_state_idle) {
        channel->reqPTY_packet_len = 39;

        /* Zero the whole thing out */
        memset(&channel->reqPTY_packet_requirev_state, 0,
               sizeof(channel->reqPTY_packet_requirev_state));

        _libssh2_debug(session, LIBSSH2_TRACE_CONN,
            "changing tty size on channel %lu/%lu",
            channel->local.id,
            channel->remote.id);

        s = channel->reqPTY_packet =
            LIBSSH2_ALLOC(session, channel->reqPTY_packet_len);

        if (!channel->reqPTY_packet) {
            libssh2_error(session, LIBSSH2_ERROR_ALLOC,
            "Unable to allocate memory for pty-request", 0);
            return -1;
        }

        *(s++) = SSH_MSG_CHANNEL_REQUEST;
        _libssh2_htonu32(s, channel->remote.id);
        s += 4;
        _libssh2_htonu32(s, sizeof("window-change") - 1);
        s += 4;
        memcpy(s, "window-change", sizeof("window-change") - 1);
        s += sizeof("window-change") - 1;

        *(s++) = 0x00; /* Don't reply */
        _libssh2_htonu32(s, width);
        s += 4;
        _libssh2_htonu32(s, height);
        s += 4;
        _libssh2_htonu32(s, width_px);
        s += 4;
        _libssh2_htonu32(s, height_px);
        s += 4;

        channel->reqPTY_state = libssh2_NB_state_created;
    }

    if (channel->reqPTY_state == libssh2_NB_state_created) {
        rc = _libssh2_transport_write(session, channel->reqPTY_packet,
                                   channel->reqPTY_packet_len);
        if (rc == PACKET_EAGAIN) {
            return rc;
        } else if (rc) {
            libssh2_error(session, rc,
                          "Unable to send window-change packet", 0);
            LIBSSH2_FREE(session, channel->reqPTY_packet);
            channel->reqPTY_packet = NULL;
            channel->reqPTY_state = libssh2_NB_state_idle;
            return rc;
        }
        LIBSSH2_FREE(session, channel->reqPTY_packet);
        channel->reqPTY_packet = NULL;
        _libssh2_htonu32(channel->reqPTY_local_channel, channel->local.id);
        channel->reqPTY_state = libssh2_NB_state_sent;

        return 0;
    }

    channel->reqPTY_state = libssh2_NB_state_idle;
    return -1;
}

LIBSSH2_API int
libssh2_channel_request_pty_size_ex(LIBSSH2_CHANNEL *channel, int width,
                                    int height, int width_px, int height_px)
{
    int rc;
    BLOCK_ADJUST(rc, channel->session,
                 channel_request_pty_size(channel, width, height, width_px,
                                          height_px));
    return rc;
}

/* Keep this an even number */
#define LIBSSH2_X11_RANDOM_COOKIE_LEN       32

/*
 * channel_x11_req
 * Request X11 forwarding
 */
static int
channel_x11_req(LIBSSH2_CHANNEL *channel, int single_connection,
                const char *auth_proto, const char *auth_cookie,
                int screen_number)
{
    LIBSSH2_SESSION *session = channel->session;
    unsigned char *s, *data;
    static const unsigned char reply_codes[3] =
        { SSH_MSG_CHANNEL_SUCCESS, SSH_MSG_CHANNEL_FAILURE, 0 };
    unsigned long data_len;
    unsigned long proto_len =
        auth_proto ? strlen(auth_proto) : (sizeof("MIT-MAGIC-COOKIE-1") - 1);
    unsigned long cookie_len =
        auth_cookie ? strlen(auth_cookie) : LIBSSH2_X11_RANDOM_COOKIE_LEN;
    int rc;

    if (channel->reqX11_state == libssh2_NB_state_idle) {
        /* 30 = packet_type(1) + channel(4) + x11_req_len(4) + "x11-req"(7) +
         * want_reply(1) + single_cnx(1) + proto_len(4) + cookie_len(4) +
         * screen_num(4) */
        channel->reqX11_packet_len = proto_len + cookie_len + 30;

        /* Zero the whole thing out */
        memset(&channel->reqX11_packet_requirev_state, 0,
               sizeof(channel->reqX11_packet_requirev_state));

        _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                       "Requesting x11-req for channel %lu/%lu: single=%d "
                       "proto=%s cookie=%s screen=%d",
                       channel->local.id, channel->remote.id,
                       single_connection,
                       auth_proto ? auth_proto : "MIT-MAGIC-COOKIE-1",
                       auth_cookie ? auth_cookie : "<random>", screen_number);

        s = channel->reqX11_packet =
            LIBSSH2_ALLOC(session, channel->reqX11_packet_len);
        if (!channel->reqX11_packet) {
            libssh2_error(session, LIBSSH2_ERROR_ALLOC,
                          "Unable to allocate memory for pty-request", 0);
            return -1;
        }

        *(s++) = SSH_MSG_CHANNEL_REQUEST;
        _libssh2_htonu32(s, channel->remote.id);
        s += 4;
        _libssh2_htonu32(s, sizeof("x11-req") - 1);
        s += 4;
        memcpy(s, "x11-req", sizeof("x11-req") - 1);
        s += sizeof("x11-req") - 1;

        *(s++) = 0x01;          /* want_reply */
        *(s++) = single_connection ? 0x01 : 0x00;

        _libssh2_htonu32(s, proto_len);
        s += 4;
        memcpy(s, auth_proto ? auth_proto : "MIT-MAGIC-COOKIE-1", proto_len);
        s += proto_len;

        _libssh2_htonu32(s, cookie_len);
        s += 4;
        if (auth_cookie) {
            memcpy(s, auth_cookie, cookie_len);
        } else {
            int i;
            /* note: the extra +1 below is necessary since the sprintf()
               loop will always write 3 bytes so the last one will write
               the trailing zero at the LIBSSH2_X11_RANDOM_COOKIE_LEN/2
               border */
            unsigned char buffer[(LIBSSH2_X11_RANDOM_COOKIE_LEN / 2) +1];

            libssh2_random(buffer, LIBSSH2_X11_RANDOM_COOKIE_LEN / 2);
            for(i = 0; i < (LIBSSH2_X11_RANDOM_COOKIE_LEN / 2); i++) {
                sprintf((char *)&s[i*2], "%02X", buffer[i]);
            }
        }
        s += cookie_len;

        _libssh2_htonu32(s, screen_number);
        s += 4;

        channel->reqX11_state = libssh2_NB_state_created;
    }

    if (channel->reqX11_state == libssh2_NB_state_created) {
        rc = _libssh2_transport_write(session, channel->reqX11_packet,
                                   channel->reqX11_packet_len);
        if (rc == PACKET_EAGAIN) {
            return rc;
        }
        if (rc) {
            libssh2_error(session, rc,
                          "Unable to send x11-req packet", 0);
            LIBSSH2_FREE(session, channel->reqX11_packet);
            channel->reqX11_packet = NULL;
            channel->reqX11_state = libssh2_NB_state_idle;
            return rc;
        }
        LIBSSH2_FREE(session, channel->reqX11_packet);
        channel->reqX11_packet = NULL;

        _libssh2_htonu32(channel->reqX11_local_channel, channel->local.id);

        channel->reqX11_state = libssh2_NB_state_sent;
    }

    if (channel->reqX11_state == libssh2_NB_state_sent) {
        rc = _libssh2_packet_requirev(session, reply_codes, &data, &data_len,
                                      1, channel->reqX11_local_channel, 4,
                                      &channel->reqX11_packet_requirev_state);
        if (rc == PACKET_EAGAIN) {
            return rc;
        } else if (rc) {
            /* TODO: call libssh2_error() here! */
            channel->reqX11_state = libssh2_NB_state_idle;
            return rc;
        }

        if (data[0] == SSH_MSG_CHANNEL_SUCCESS) {
            LIBSSH2_FREE(session, data);
            channel->reqX11_state = libssh2_NB_state_idle;
            return 0;
        }
    }

    LIBSSH2_FREE(session, data);
    libssh2_error(session, LIBSSH2_ERROR_CHANNEL_REQUEST_DENIED,
                  "Unable to complete request for channel x11-req", 0);
    return -1;
}

/*
 * libssh2_channel_x11_req_ex
 * Request X11 forwarding
 */
LIBSSH2_API int
libssh2_channel_x11_req_ex(LIBSSH2_CHANNEL *channel, int single_connection,
                           const char *auth_proto, const char *auth_cookie,
                           int screen_number)
{
    int rc;
    BLOCK_ADJUST(rc, channel->session,
                 channel_x11_req(channel, single_connection, auth_proto,
                                 auth_cookie, screen_number));
    return rc;
}


/*
 * _libssh2_channel_process_startup
 *
 * Primitive for libssh2_channel_(shell|exec|subsystem)
 */
int
_libssh2_channel_process_startup(LIBSSH2_CHANNEL *channel,
                                 const char *request, unsigned int request_len,
                                 const char *message, unsigned int message_len)
{
    LIBSSH2_SESSION *session = channel->session;
    unsigned char *s, *data;
    static const unsigned char reply_codes[3] =
        { SSH_MSG_CHANNEL_SUCCESS, SSH_MSG_CHANNEL_FAILURE, 0 };
    unsigned long data_len;
    int rc;

    if (channel->process_state == libssh2_NB_state_idle) {
        /* 10 = packet_type(1) + channel(4) + request_len(4) + want_reply(1) */
        channel->process_packet_len = request_len + 10;

        /* Zero the whole thing out */
        memset(&channel->process_packet_requirev_state, 0,
               sizeof(channel->process_packet_requirev_state));

        if (message) {
            channel->process_packet_len += message_len + 4;
        }

        _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                       "starting request(%s) on channel %lu/%lu, message=%s",
                       request, channel->local.id, channel->remote.id,
                       message);
        s = channel->process_packet =
            LIBSSH2_ALLOC(session, channel->process_packet_len);
        if (!channel->process_packet) {
            libssh2_error(session, LIBSSH2_ERROR_ALLOC,
                          "Unable to allocate memory for channel-process request",
                          0);
            return LIBSSH2_ERROR_ALLOC;
        }

        *(s++) = SSH_MSG_CHANNEL_REQUEST;
        _libssh2_htonu32(s, channel->remote.id);
        s += 4;
        _libssh2_htonu32(s, request_len);
        s += 4;
        memcpy(s, request, request_len);
        s += request_len;

        *(s++) = 0x01;

        if (message) {
            _libssh2_htonu32(s, message_len);
            s += 4;
            memcpy(s, message, message_len);
            s += message_len;
        }

        channel->process_state = libssh2_NB_state_created;
    }

    if (channel->process_state == libssh2_NB_state_created) {
        rc = _libssh2_transport_write(session, channel->process_packet,
                                   channel->process_packet_len);
        if (rc == PACKET_EAGAIN) {
            return rc;
        }
        else if (rc) {
            libssh2_error(session, rc,
                          "Unable to send channel request", 0);
            LIBSSH2_FREE(session, channel->process_packet);
            channel->process_packet = NULL;
            channel->process_state = libssh2_NB_state_idle;
            return rc;
        }
        LIBSSH2_FREE(session, channel->process_packet);
        channel->process_packet = NULL;

        _libssh2_htonu32(channel->process_local_channel, channel->local.id);

        channel->process_state = libssh2_NB_state_sent;
    }

    if (channel->process_state == libssh2_NB_state_sent) {
        rc = _libssh2_packet_requirev(session, reply_codes, &data, &data_len,
                                      1, channel->process_local_channel, 4,
                                      &channel->process_packet_requirev_state);
        if (rc == PACKET_EAGAIN) {
            return rc;
        } else if (rc) {
            channel->process_state = libssh2_NB_state_idle;
            libssh2_error(session, rc,
                          "Failed waiting for channel success", 0);
            return rc;
        }

        if (data[0] == SSH_MSG_CHANNEL_SUCCESS) {
            LIBSSH2_FREE(session, data);
            channel->process_state = libssh2_NB_state_idle;
            return 0;
        }
    }

    LIBSSH2_FREE(session, data);
    libssh2_error(session, LIBSSH2_ERROR_CHANNEL_REQUEST_DENIED,
                  "Unable to complete request for channel-process-startup", 0);
    channel->process_state = libssh2_NB_state_idle;
    return LIBSSH2_ERROR_CHANNEL_REQUEST_DENIED;
}

/*
 * libssh2_channel_process_startup
 *
 * Primitive for libssh2_channel_(shell|exec|subsystem)
 */
LIBSSH2_API int
libssh2_channel_process_startup(LIBSSH2_CHANNEL *channel,
                                const char *req, unsigned int req_len,
                                const char *msg, unsigned int msg_len)
{
    int rc;
    BLOCK_ADJUST(rc, channel->session,
                 _libssh2_channel_process_startup(channel, req, req_len,
                                                  msg, msg_len));
    return rc;
}


/*
 * libssh2_channel_set_blocking
 *
 * Set a channel's BEHAVIOR blocking on or off. The socket will remain non-
 * blocking.
 */
LIBSSH2_API void
libssh2_channel_set_blocking(LIBSSH2_CHANNEL * channel, int blocking)
{
    (void) _libssh2_session_set_blocking(channel->session, blocking);
}

/*
 * _libssh2_channel_flush
 *
 * Flush data from one (or all) stream
 * Returns number of bytes flushed, or negative on failure
 */
int
_libssh2_channel_flush(LIBSSH2_CHANNEL *channel, int streamid)
{
    if (channel->flush_state == libssh2_NB_state_idle) {
        LIBSSH2_PACKET *packet =
            _libssh2_list_first(&channel->session->packets);
        channel->flush_refund_bytes = 0;
        channel->flush_flush_bytes = 0;

        while (packet) {
            LIBSSH2_PACKET *next = _libssh2_list_next(&packet->node);
            unsigned char packet_type = packet->data[0];

            if (((packet_type == SSH_MSG_CHANNEL_DATA)
                 || (packet_type == SSH_MSG_CHANNEL_EXTENDED_DATA))
                && (_libssh2_ntohu32(packet->data + 1) == channel->local.id)) {
                /* It's our channel at least */
                long packet_stream_id =
                    (packet_type == SSH_MSG_CHANNEL_DATA) ? 0 :
                    _libssh2_ntohu32(packet->data + 5);
                if ((streamid == LIBSSH2_CHANNEL_FLUSH_ALL)
                    || ((packet_type == SSH_MSG_CHANNEL_EXTENDED_DATA)
                        && ((streamid == LIBSSH2_CHANNEL_FLUSH_EXTENDED_DATA)
                            || (streamid == packet_stream_id)))
                    || ((packet_type == SSH_MSG_CHANNEL_DATA)
                        && (streamid == 0))) {
                    int bytes_to_flush = packet->data_len - packet->data_head;

                    _libssh2_debug(channel->session, LIBSSH2_TRACE_CONN,
                                   "Flushing %d bytes of data from stream "
                                   "%lu on channel %lu/%lu",
                                   bytes_to_flush, packet_stream_id,
                                   channel->local.id, channel->remote.id);

                    /* It's one of the streams we wanted to flush */
                    channel->flush_refund_bytes += packet->data_len - 13;
                    channel->flush_flush_bytes += bytes_to_flush;

                    LIBSSH2_FREE(channel->session, packet->data);

                    /* remove this packet from the parent's list */
                    _libssh2_list_remove(&packet->node);
                    LIBSSH2_FREE(channel->session, packet);
                }
            }
            packet = next;
        }

        channel->flush_state = libssh2_NB_state_created;
    }

    if (channel->flush_refund_bytes) {
        int rc;

        rc = _libssh2_channel_receive_window_adjust(channel,
                                                    channel->flush_refund_bytes,
                                                    0, NULL);
        if (rc == PACKET_EAGAIN)
            return rc;
    }

    channel->flush_state = libssh2_NB_state_idle;

    return channel->flush_flush_bytes;
}

/*
 * libssh2_channel_flush_ex
 *
 * Flush data from one (or all) stream
 * Returns number of bytes flushed, or negative on failure
 */
LIBSSH2_API int
libssh2_channel_flush_ex(LIBSSH2_CHANNEL *channel, int stream)
{
    int rc;
    BLOCK_ADJUST(rc, channel->session,
                 _libssh2_channel_flush(channel, stream));
    return rc;
}

/*
 * libssh2_channel_get_exit_status
 *
 * Return the channel's program exit status
 */
LIBSSH2_API int
libssh2_channel_get_exit_status(LIBSSH2_CHANNEL * channel)
{
    return channel->exit_status;
}

/*
 * _libssh2_channel_receive_window_adjust
 *
 * Adjust the receive window for a channel by adjustment bytes. If the amount
 * to be adjusted is less than LIBSSH2_CHANNEL_MINADJUST and force is 0 the
 * adjustment amount will be queued for a later packet.
 *
 */
int
_libssh2_channel_receive_window_adjust(LIBSSH2_CHANNEL * channel,
                                       unsigned long adjustment,
                                       unsigned char force,
                                       unsigned int *store)
{
    int rc;

    if (channel->adjust_state == libssh2_NB_state_idle) {
        if (!force
            && (adjustment + channel->adjust_queue <
                LIBSSH2_CHANNEL_MINADJUST)) {
            _libssh2_debug(channel->session, LIBSSH2_TRACE_CONN,
                           "Queueing %lu bytes for receive window adjustment "
                           "for channel %lu/%lu",
                           adjustment, channel->local.id, channel->remote.id);
            channel->adjust_queue += adjustment;
            if(store)
                *store = channel->remote.window_size;
            return 0;
        }

        if (!adjustment && !channel->adjust_queue) {
            if(store)
                *store = channel->remote.window_size;
            return 0;
        }

        adjustment += channel->adjust_queue;
        channel->adjust_queue = 0;

        /* Adjust the window based on the block we just freed */
        channel->adjust_adjust[0] = SSH_MSG_CHANNEL_WINDOW_ADJUST;
        _libssh2_htonu32(&channel->adjust_adjust[1], channel->remote.id);
        _libssh2_htonu32(&channel->adjust_adjust[5], adjustment);
        _libssh2_debug(channel->session, LIBSSH2_TRACE_CONN,
                       "Adjusting window %lu bytes for data on "
                       "channel %lu/%lu",
                       adjustment, channel->local.id, channel->remote.id);

        channel->adjust_state = libssh2_NB_state_created;
    }

    rc = _libssh2_transport_write(channel->session, channel->adjust_adjust, 9);
    if (rc == PACKET_EAGAIN) {
        return rc;
    }
    else if (rc) {
        libssh2_error(channel->session, LIBSSH2_ERROR_SOCKET_SEND,
                      "Unable to send transfer-window adjustment packet, "
                      "deferring", 0);
        channel->adjust_queue = adjustment;
        return rc;
    }
    else {
        channel->remote.window_size += adjustment;
    }

    channel->adjust_state = libssh2_NB_state_idle;

    if(store)
        *store = channel->remote.window_size;
    return 0;
}

/*
 * libssh2_channel_receive_window_adjust
 *
 * DEPRECATED
 *
 * Adjust the receive window for a channel by adjustment bytes. If the amount
 * to be adjusted is less than LIBSSH2_CHANNEL_MINADJUST and force is 0 the
 * adjustment amount will be queued for a later packet.
 *
 * Returns the new size of the receive window (as understood by remote end).
 * Note that it might return EAGAIN too which is highly stupid.
 *
 */
LIBSSH2_API unsigned long
libssh2_channel_receive_window_adjust(LIBSSH2_CHANNEL *channel,
                                      unsigned long adj,
                                      unsigned char force)
{
    unsigned int window;
    int rc;
    BLOCK_ADJUST(rc, channel->session,
                 _libssh2_channel_receive_window_adjust(channel, adj,
                                                        force, &window));

    /* stupid - but this is how it was made to work before and this is just
       kept for backwards compatibility */
    return rc?(unsigned long)rc:window;
}

/*
 * libssh2_channel_receive_window_adjust2
 *
 * Adjust the receive window for a channel by adjustment bytes. If the amount
 * to be adjusted is less than LIBSSH2_CHANNEL_MINADJUST and force is 0 the
 * adjustment amount will be queued for a later packet.
 *
 * Stores the new size of the receive window in the data 'window' points to.
 *
 * Returns the "normal" error code: 0 for success, negative for failure.
 */
LIBSSH2_API int
libssh2_channel_receive_window_adjust2(LIBSSH2_CHANNEL *channel,
                                       unsigned long adj,
                                       unsigned char force,
                                       unsigned int *window)
{
    int rc;
    BLOCK_ADJUST(rc, channel->session,
                 _libssh2_channel_receive_window_adjust(channel, adj, force,
                                                        window));
    return rc;
}

int
_libssh2_channel_extended_data(LIBSSH2_CHANNEL *channel, int ignore_mode)
{
    if (channel->extData2_state == libssh2_NB_state_idle) {
        _libssh2_debug(channel->session, LIBSSH2_TRACE_CONN,
                       "Setting channel %lu/%lu handle_extended_data"
                       " mode to %d",
                       channel->local.id, channel->remote.id, ignore_mode);
        channel->remote.extended_data_ignore_mode = ignore_mode;

        channel->extData2_state = libssh2_NB_state_created;
    }

    if (channel->extData2_state == libssh2_NB_state_idle) {
        if (ignore_mode == LIBSSH2_CHANNEL_EXTENDED_DATA_IGNORE) {
            int rc =
                _libssh2_channel_flush(channel,
                                       LIBSSH2_CHANNEL_FLUSH_EXTENDED_DATA);
            if(PACKET_EAGAIN == rc)
                return rc;
        }
    }

    channel->extData2_state = libssh2_NB_state_idle;
    return 0;
}

/*
 * libssh2_channel_handle_extended_data2()
 *
 */
LIBSSH2_API int
libssh2_channel_handle_extended_data2(LIBSSH2_CHANNEL *channel,
                                      int mode)
{
    int rc;
    BLOCK_ADJUST(rc, channel->session, _libssh2_channel_extended_data(channel,
                                                                      mode));
    return rc;
}

/*
 * libssh2_channel_handle_extended_data
 *
 * DEPRECATED DO NOTE USE!
 *
 * How should extended data look to the calling app?  Keep it in separate
 * channels[_read() _read_stdder()]? (NORMAL) Merge the extended data to the
 * standard data? [everything via _read()]? (MERGE) Ignore it entirely [toss
 * out packets as they come in]? (IGNORE)
 */
LIBSSH2_API void
libssh2_channel_handle_extended_data(LIBSSH2_CHANNEL *channel,
                                     int ignore_mode)
{
    (void)libssh2_channel_handle_extended_data2(channel, ignore_mode);
}



/*
 * _libssh2_channel_read
 *
 * Read data from a channel
 *
 * It is important to not return 0 until the currently read channel is
 * complete. If we read stuff from the wire but it was no payload data to fill
 * in the buffer with, we MUST make sure to return PACKET_EAGAIN.
 */
ssize_t _libssh2_channel_read(LIBSSH2_CHANNEL *channel, int stream_id,
                              char *buf, size_t buflen)
{
    LIBSSH2_SESSION *session = channel->session;
    int rc;
    int bytes_read = 0;
    int bytes_want;
    int unlink_packet;
    LIBSSH2_PACKET *read_packet;
    LIBSSH2_PACKET *read_next;

    if (channel->read_state == libssh2_NB_state_idle) {
        _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                       "channel_read() wants %d bytes from channel %lu/%lu "
                       "stream #%d",
                       (int) buflen, channel->local.id, channel->remote.id,
                       stream_id);
        channel->read_state = libssh2_NB_state_created;
    }
    rc = 1; /* set to >0 to let the while loop start */

    /* Process all pending incoming packets in all states in order to "even
       out" the network readings. Tests prove that this way produces faster
       transfers. */
    while (rc > 0)
        rc = _libssh2_transport_read(session);

    if ((rc < 0) && (rc != PACKET_EAGAIN)) {
        libssh2_error(session, rc, "tranport read", 0);
        return rc;
    }

    /*
     * =============================== NOTE ===============================
     * I know this is very ugly and not a really good use of "goto", but
     * this case statement would be even uglier to do it any other way
     */
    if (channel->read_state == libssh2_NB_state_jump1) {
        goto channel_read_ex_point1;
    }

    read_packet = _libssh2_list_first(&session->packets);
    while (read_packet && (bytes_read < (int) buflen)) {
        /* previously this loop condition also checked for
           !channel->remote.close but we cannot let it do this:

           We may have a series of packets to read that are still pending even
           if a close has been received. Acknowledging the close too early
           makes us flush buffers prematurely and loose data.
        */

        LIBSSH2_PACKET *readpkt = read_packet;

        /* In case packet gets destroyed during this iteration */
        read_next = _libssh2_list_next(&readpkt->node);

        channel->read_local_id =
            _libssh2_ntohu32(readpkt->data + 1);

        /*
         * Either we asked for a specific extended data stream
         * (and data was available),
         * or the standard stream (and data was available),
         * or the standard stream with extended_data_merge
         * enabled and data was available
         */
        if ((stream_id
             && (readpkt->data[0] == SSH_MSG_CHANNEL_EXTENDED_DATA)
             && (channel->local.id == channel->read_local_id)
             && (stream_id == (int) _libssh2_ntohu32(readpkt->data + 5)))
            || (!stream_id && (readpkt->data[0] == SSH_MSG_CHANNEL_DATA)
                && (channel->local.id == channel->read_local_id))
            || (!stream_id
                && (readpkt->data[0] == SSH_MSG_CHANNEL_EXTENDED_DATA)
                && (channel->local.id == channel->read_local_id)
                && (channel->remote.extended_data_ignore_mode ==
                    LIBSSH2_CHANNEL_EXTENDED_DATA_MERGE))) {

            /* figure out much more data we want to read */
            bytes_want = buflen - bytes_read;
            unlink_packet = FALSE;

            if (bytes_want >= (int) (readpkt->data_len - readpkt->data_head)) {
                /* we want more than this node keeps, so adjust the number and
                   delete this node after the copy */
                bytes_want = readpkt->data_len - readpkt->data_head;
                unlink_packet = TRUE;
            }

            _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                           "channel_read() got %d of data from %lu/%lu/%d%s",
                           bytes_want, channel->local.id,
                           channel->remote.id, stream_id,
                           unlink_packet?" [ul]":"");

            /* copy data from this struct to the target buffer */
            memcpy(&buf[bytes_read],
                   &readpkt->data[readpkt->data_head], bytes_want);

            /* advance pointer and counter */
            readpkt->data_head += bytes_want;
            bytes_read += bytes_want;

            /* if drained, remove from list */
            if (unlink_packet) {
                /* detach readpkt from session->packets list */
                _libssh2_list_remove(&readpkt->node);

                LIBSSH2_FREE(session, readpkt->data);
                LIBSSH2_FREE(session, readpkt);
            }
        }

        /* check the next struct in the chain */
        read_packet = read_next;
    }

    if (!bytes_read) {
        channel->read_state = libssh2_NB_state_idle;

        /* If the channel is already at EOF or even closed, we need to signal
           that back. We may have gotten that info while draining the incoming
           transport layer until EAGAIN so we must not be fooled by that
           return code. */
        if(channel->remote.eof || channel->remote.close)
            return 0;
        else
            /* if the transport layer said EAGAIN then we say so as well */
            return (rc == PACKET_EAGAIN)?rc:0;
    }
    else
        /* make sure we remain in the created state to focus on emptying the
           data we already have in the packet brigade before we try to read
           more off the network again */
        channel->read_state = libssh2_NB_state_created;

    if(channel->remote.window_size < (LIBSSH2_CHANNEL_WINDOW_DEFAULT*300)) {
        /* the window is getting too narrow, expand it! */

      channel_read_ex_point1:
        channel->read_state = libssh2_NB_state_jump1;
        /* the actual window adjusting may not finish so we need to deal with
           this special state here */
        rc = _libssh2_channel_receive_window_adjust(channel,
                                                    (LIBSSH2_CHANNEL_WINDOW_DEFAULT*600), 0, NULL);
        if (rc == PACKET_EAGAIN)
            return rc;

        _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                       "channel_read() filled %d adjusted %d",
                       bytes_read, buflen);
        /* continue in 'created' state to drain the already read packages
           first before starting to empty the socket further */
        channel->read_state = libssh2_NB_state_created;
    }

    return bytes_read;
}

/*
 * libssh2_channel_read_ex
 *
 * Read data from a channel (blocking or non-blocking depending on set state)
 *
 * When this is done non-blocking, it is important to not return 0 until the
 * currently read channel is complete. If we read stuff from the wire but it
 * was no payload data to fill in the buffer with, we MUST make sure to return
 * PACKET_EAGAIN.
 */
LIBSSH2_API ssize_t
libssh2_channel_read_ex(LIBSSH2_CHANNEL *channel, int stream_id, char *buf,
                        size_t buflen)
{
    int rc;
    BLOCK_ADJUST(rc, channel->session,
                 _libssh2_channel_read(channel, stream_id, buf, buflen));
    return rc;
}

/*
 * _libssh2_channel_packet_data_len
 *
 * Return the size of the data block of the current packet, or 0 if there
 * isn't a packet.
 */
unsigned long
_libssh2_channel_packet_data_len(LIBSSH2_CHANNEL * channel, int stream_id)
{
    LIBSSH2_SESSION *session = channel->session;
    LIBSSH2_PACKET *read_packet;
    uint32_t read_local_id;

    read_packet = _libssh2_list_first(&session->packets);
    if (read_packet == NULL)
        return 0;

    while (read_packet) {
        read_local_id = _libssh2_ntohu32(read_packet->data + 1);

        /*
         * Either we asked for a specific extended data stream
         * (and data was available),
         * or the standard stream (and data was available),
         * or the standard stream with extended_data_merge
         * enabled and data was available
         */
        if ((stream_id
             && (read_packet->data[0] == SSH_MSG_CHANNEL_EXTENDED_DATA)
             && (channel->local.id == read_local_id)
             && (stream_id == (int) _libssh2_ntohu32(read_packet->data + 5)))
            ||
            (!stream_id
             && (read_packet->data[0] == SSH_MSG_CHANNEL_DATA)
             && (channel->local.id == read_local_id))
            ||
            (!stream_id
             && (read_packet->data[0] == SSH_MSG_CHANNEL_EXTENDED_DATA)
             && (channel->local.id == read_local_id)
             && (channel->remote.extended_data_ignore_mode
                 == LIBSSH2_CHANNEL_EXTENDED_DATA_MERGE)))
        {
            return (read_packet->data_len - read_packet->data_head);
        }
        read_packet = _libssh2_list_next(&read_packet->node);
    }

    return 0;
}

/*
 * _libssh2_channel_write
 *
 * Send data to a channel. Note that if this returns EAGAIN or simply didn't
 * send the entire packet, the caller must call this function again with the
 * SAME input arguments.
 *
 * Returns: number of bytes sent, or if it returns a negative number, that is
 * the error code!
 */
ssize_t
_libssh2_channel_write(LIBSSH2_CHANNEL *channel, int stream_id,
                       const char *buf, size_t buflen)
{
    LIBSSH2_SESSION *session = channel->session;
    int rc;
    ssize_t wrote = 0; /* counter for this specific this call */

    /* In theory we could split larger buffers into several smaller packets,
     * but for now we instead only deal with the first 32K in this call and
     * assume the app will call it again with the rest! The 32K is a
     * conservative limit based on the text in RFC4253 section 6.1.
     */
    if(buflen > 32768)
        buflen = 32768;

    if (channel->write_state == libssh2_NB_state_idle) {
        channel->write_bufwrote = 0;

        _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                       "Writing %d bytes on channel %lu/%lu, stream #%d",
                       (int) buflen, channel->local.id, channel->remote.id,
                       stream_id);

        if (channel->local.close) {
            libssh2_error(session, LIBSSH2_ERROR_CHANNEL_CLOSED,
                          "We've already closed this channel", 0);
            return LIBSSH2_ERROR_CHANNEL_CLOSED;
        }

        if (channel->local.eof) {
            libssh2_error(session, LIBSSH2_ERROR_CHANNEL_EOF_SENT,
                          "EOF has already been sight, data might be ignored",
                          0);
        }

        /* [13] 9 = packet_type(1) + channelno(4) [ + streamid(4) ] +
           buflen(4) */
        channel->write_packet_len = buflen + (stream_id ? 13 : 9);
        channel->write_packet =
            LIBSSH2_ALLOC(session, channel->write_packet_len);
        if (!channel->write_packet) {
            libssh2_error(session, LIBSSH2_ERROR_ALLOC,
                          "Unable to allocte space for data transmission packet",
                          0);
            return LIBSSH2_ERROR_ALLOC;
        }

        channel->write_state = libssh2_NB_state_allocated;
    }

    /* Deduct the amount that has already been sent, and set buf accordingly. */
    buflen -= channel->write_bufwrote;
    buf += channel->write_bufwrote;

    while (buflen > 0) {
        if (channel->write_state == libssh2_NB_state_allocated) {
            channel->write_bufwrite = buflen;
            channel->write_s = channel->write_packet;

            *(channel->write_s++) =
                stream_id ? SSH_MSG_CHANNEL_EXTENDED_DATA :
                SSH_MSG_CHANNEL_DATA;
            _libssh2_htonu32(channel->write_s, channel->remote.id);
            channel->write_s += 4;
            if (stream_id) {
                _libssh2_htonu32(channel->write_s, stream_id);
                channel->write_s += 4;
            }

            /* drain the incoming flow first */
            do
                rc = _libssh2_transport_read(session);
            while (rc > 0);

            if(channel->local.window_size <= 0) {
                /* there's no more room for data so we stop sending now */
                break;
            }

            /* Don't exceed the remote end's limits */
            /* REMEMBER local means local as the SOURCE of the data */
            if (channel->write_bufwrite > channel->local.window_size) {
                _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                               "Splitting write block due to %lu byte "
                               "window_size on %lu/%lu/%d",
                               channel->local.window_size, channel->local.id,
                               channel->remote.id, stream_id);
                channel->write_bufwrite = channel->local.window_size;
            }
            if (channel->write_bufwrite > channel->local.packet_size) {
                _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                               "Splitting write block due to %lu byte "
                               "packet_size on %lu/%lu/%d",
                               channel->local.packet_size, channel->local.id,
                               channel->remote.id, stream_id);
                channel->write_bufwrite = channel->local.packet_size;
            }
            _libssh2_htonu32(channel->write_s, channel->write_bufwrite);
            channel->write_s += 4;
            memcpy(channel->write_s, buf, channel->write_bufwrite);
            channel->write_s += channel->write_bufwrite;

            _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                           "Sending %d bytes on channel %lu/%lu, stream_id=%d",
                           (int) channel->write_bufwrite, channel->local.id,
                           channel->remote.id, stream_id);

            channel->write_state = libssh2_NB_state_created;
        }

        if (channel->write_state == libssh2_NB_state_created) {
            rc = _libssh2_transport_write(session, channel->write_packet,
                                          channel->write_s -
                                          channel->write_packet);
            if (rc == PACKET_EAGAIN) {
                libssh2_error(session, rc,
                              "Unable to send channel data", 0);
                return rc;
            }
            else if (rc) {
                libssh2_error(session, rc,
                              "Unable to send channel data", 0);
                LIBSSH2_FREE(session, channel->write_packet);
                channel->write_packet = NULL;
                channel->write_state = libssh2_NB_state_idle;
                return rc;
            }
            /* Shrink local window size */
            channel->local.window_size -= channel->write_bufwrite;

            /* Adjust buf for next iteration */
            buflen -= channel->write_bufwrite;
            buf += channel->write_bufwrite;
            channel->write_bufwrote += channel->write_bufwrite;
            wrote += channel->write_bufwrite;

            channel->write_state = libssh2_NB_state_allocated;
        }
    }

    LIBSSH2_FREE(session, channel->write_packet);
    channel->write_packet = NULL;

    channel->write_state = libssh2_NB_state_idle;

    return wrote;
}

/*
 * libssh2_channel_write_ex
 *
 * Send data to a channel
 */
LIBSSH2_API ssize_t
libssh2_channel_write_ex(LIBSSH2_CHANNEL *channel, int stream_id,
                         const char *buf, size_t buflen)
{
    ssize_t rc;
    BLOCK_ADJUST(rc, channel->session,
                 _libssh2_channel_write(channel, stream_id, buf, buflen));
    return rc;
}

/*
 * channel_send_eof
 *
 * Send EOF on channel
 */
static int channel_send_eof(LIBSSH2_CHANNEL *channel)
{
    LIBSSH2_SESSION *session = channel->session;
    unsigned char packet[5];    /* packet_type(1) + channelno(4) */
    int rc;

    _libssh2_debug(session, LIBSSH2_TRACE_CONN, "Sending EOF on channel %lu/%lu",
                   channel->local.id, channel->remote.id);
    packet[0] = SSH_MSG_CHANNEL_EOF;
    _libssh2_htonu32(packet + 1, channel->remote.id);
    rc = _libssh2_transport_write(session, packet, 5);
    if (rc == PACKET_EAGAIN) {
        return rc;
    }
    else if (rc) {
        libssh2_error(session, LIBSSH2_ERROR_SOCKET_SEND,
                      "Unable to send EOF on channel", 0);
        return LIBSSH2_ERROR_SOCKET_SEND;
    }
    channel->local.eof = 1;

    return 0;
}

/*
 * libssh2_channel_send_eof
 *
 * Send EOF on channel
 */
LIBSSH2_API int
libssh2_channel_send_eof(LIBSSH2_CHANNEL *channel)
{
    int rc;
    BLOCK_ADJUST(rc, channel->session, channel_send_eof(channel));
    return rc;
}

/*
 * libssh2_channel_eof
 *
 * Read channel's eof status
 */
LIBSSH2_API int
libssh2_channel_eof(LIBSSH2_CHANNEL * channel)
{
    LIBSSH2_SESSION *session = channel->session;
    LIBSSH2_PACKET *packet = _libssh2_list_first(&session->packets);

    while (packet) {
        if (((packet->data[0] == SSH_MSG_CHANNEL_DATA)
             || (packet->data[0] == SSH_MSG_CHANNEL_EXTENDED_DATA))
            && (channel->local.id == _libssh2_ntohu32(packet->data + 1))) {
            /* There's data waiting to be read yet, mask the EOF status */
            return 0;
        }
        packet = _libssh2_list_next(&packet->node);
    }

    return channel->remote.eof;
}

/*
 * channel_wait_eof
 *
 * Awaiting channel EOF
 */
static int channel_wait_eof(LIBSSH2_CHANNEL *channel)
{
    LIBSSH2_SESSION *session = channel->session;
    int rc;

    if (channel->wait_eof_state == libssh2_NB_state_idle) {
        _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                       "Awaiting close of channel %lu/%lu", channel->local.id,
                       channel->remote.id);

        channel->wait_eof_state = libssh2_NB_state_created;
    }

    /*
     * While channel is not eof, read more packets from the network.
     * Either the EOF will be set or network timeout will occur.
     */
    do {
        if (channel->remote.eof) {
            break;
        }
        rc = _libssh2_transport_read(session);
        if (rc == PACKET_EAGAIN) {
            return rc;
        }
        else if (rc < 0) {
            channel->wait_eof_state = libssh2_NB_state_idle;
            return -1;
        }
    } while (1);

    channel->wait_eof_state = libssh2_NB_state_idle;

    return 0;
}

/*
 * libssh2_channel_wait_eof
 *
 * Awaiting channel EOF
 */
LIBSSH2_API int
libssh2_channel_wait_eof(LIBSSH2_CHANNEL *channel)
{
    int rc;
    BLOCK_ADJUST(rc, channel->session, channel_wait_eof(channel));
    return rc;
}

static int
channel_close(LIBSSH2_CHANNEL * channel)
{
    LIBSSH2_SESSION *session = channel->session;
    int rc = 0;
    int retcode;

    if (channel->local.close) {
        /* Already closed, act like we sent another close,
         * even though we didn't... shhhhhh */
        channel->close_state = libssh2_NB_state_idle;
        return 0;
    }

    if (channel->close_state == libssh2_NB_state_idle) {
        _libssh2_debug(session, LIBSSH2_TRACE_CONN, "Closing channel %lu/%lu",
                       channel->local.id, channel->remote.id);

        channel->close_packet[0] = SSH_MSG_CHANNEL_CLOSE;
        _libssh2_htonu32(channel->close_packet + 1, channel->remote.id);

        channel->close_state = libssh2_NB_state_created;
    }

    if (channel->close_state == libssh2_NB_state_created) {
        retcode = _libssh2_transport_write(session, channel->close_packet, 5);
        if (retcode == PACKET_EAGAIN) {
            return retcode;
        } else if (retcode) {
            libssh2_error(session, retcode,
                          "Unable to send close-channel request", 0);
            channel->close_state = libssh2_NB_state_idle;
            return retcode;
        }

        channel->close_state = libssh2_NB_state_sent;
    }

    if (channel->close_state == libssh2_NB_state_sent) {
        /* We must wait for the remote SSH_MSG_CHANNEL_CLOSE message */

        while (!channel->remote.close && !rc) {
            rc = _libssh2_transport_read(session);
        }
    }

    if(rc != LIBSSH2_ERROR_EAGAIN) {
        /* set the local close state first when we're perfectly confirmed to not
           do any more EAGAINs */
        channel->local.close = 1;

        /* We call the callback last in this function to make it keep the local
           data as long as EAGAIN is returned. */
        if (channel->close_cb) {
            LIBSSH2_CHANNEL_CLOSE(session, channel);
        }

        channel->close_state = libssh2_NB_state_idle;
    }

    /* return 0 or an error */
    return rc>=0?0:rc;
}

/*
 * libssh2_channel_close
 *
 * Close a channel
 */
LIBSSH2_API int
libssh2_channel_close(LIBSSH2_CHANNEL *channel)
{
    int rc;
    BLOCK_ADJUST(rc, channel->session, channel_close(channel) );
    return rc;
}

/*
 * channel_wait_closed
 *
 * Awaiting channel close after EOF
 */
static int channel_wait_closed(LIBSSH2_CHANNEL *channel)
{
    LIBSSH2_SESSION *session = channel->session;
    int rc;

    if (!libssh2_channel_eof(channel)) {
        libssh2_error(session, LIBSSH2_ERROR_INVAL,
                      "libssh2_channel_wait_closed() invoked when channel is "
                      "not in EOF state",
                      0);
        return -1;
    }

    if (channel->wait_closed_state == libssh2_NB_state_idle) {
        _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                       "Awaiting close of channel %lu/%lu", channel->local.id,
                       channel->remote.id);

        channel->wait_closed_state = libssh2_NB_state_created;
    }

    /*
     * While channel is not closed, read more packets from the network.
     * Either the channel will be closed or network timeout will occur.
     */
    if (!channel->remote.close) {
        do {
            rc = _libssh2_transport_read(session);
            if (channel->remote.close)
                /* it is now closed, move on! */
                break;
        } while (rc > 0);
        if(rc < 0)
            return rc;
    }

    channel->wait_closed_state = libssh2_NB_state_idle;

    return 0;
}

/*
 * libssh2_channel_wait_closed
 *
 * Awaiting channel close after EOF
 */
LIBSSH2_API int
libssh2_channel_wait_closed(LIBSSH2_CHANNEL *channel)
{
    int rc;
    BLOCK_ADJUST(rc, channel->session, channel_wait_closed(channel));
    return rc;
}

/*
 * _libssh2_channel_free
 *
 * Make sure a channel is closed, then remove the channel from the session
 * and free its resource(s)
 *
 * Returns 0 on success, negative on failure
 */
int _libssh2_channel_free(LIBSSH2_CHANNEL *channel)
{
    LIBSSH2_SESSION *session = channel->session;
    unsigned char channel_id[4];
    unsigned char *data;
    unsigned long data_len;
    int rc;

    assert(session);

    if (channel->free_state == libssh2_NB_state_idle) {
        _libssh2_debug(session, LIBSSH2_TRACE_CONN,
                       "Freeing channel %lu/%lu resources", channel->local.id,
                       channel->remote.id);

        channel->free_state = libssh2_NB_state_created;
    }

    /* Allow channel freeing even when the socket has lost its connection */
    if (!channel->local.close
        && (session->socket_state == LIBSSH2_SOCKET_CONNECTED)) {
        rc = channel_close(channel);

        if(rc == PACKET_EAGAIN)
            return rc;
        else if (rc < 0) {
            channel->free_state = libssh2_NB_state_idle;
            return rc;
        }
    }

    channel->free_state = libssh2_NB_state_idle;

    /*
     * channel->remote.close *might* not be set yet, Well...
     * We've sent the close packet, what more do you want?
     * Just let packet_add ignore it when it finally arrives
     */

    /* Clear out packets meant for this channel */
    _libssh2_htonu32(channel_id, channel->local.id);
    while ((_libssh2_packet_ask(session, SSH_MSG_CHANNEL_DATA, &data,
                                &data_len, 1, channel_id, 4) >= 0)
           ||
           (_libssh2_packet_ask(session, SSH_MSG_CHANNEL_EXTENDED_DATA, &data,
                                &data_len, 1, channel_id, 4) >= 0)) {
        LIBSSH2_FREE(session, data);
    }

    /* free "channel_type" */
    if (channel->channel_type) {
        LIBSSH2_FREE(session, channel->channel_type);
    }

    /* Unlink from channel list */
    _libssh2_list_remove(&channel->node);

    /*
     * Make sure all memory used in the state variables are free
     */
    if (channel->setenv_packet) {
        LIBSSH2_FREE(session, channel->setenv_packet);
    }
    if (channel->reqPTY_packet) {
        LIBSSH2_FREE(session, channel->reqPTY_packet);
    }
    if (channel->reqX11_packet) {
        LIBSSH2_FREE(session, channel->reqX11_packet);
    }
    if (channel->process_packet) {
        LIBSSH2_FREE(session, channel->process_packet);
    }
    if (channel->write_packet) {
        LIBSSH2_FREE(session, channel->write_packet);
    }

    LIBSSH2_FREE(session, channel);

    return 0;
}

/*
 * libssh2_channel_free
 *
 * Make sure a channel is closed, then remove the channel from the session
 * and free its resource(s)
 *
 * Returns 0 on success, -1 on failure
 */
LIBSSH2_API int
libssh2_channel_free(LIBSSH2_CHANNEL *channel)
{
    int rc;
    BLOCK_ADJUST(rc, channel->session, _libssh2_channel_free(channel));
    return rc;
}
/*
 * libssh2_channel_window_read_ex
 *
 * Check the status of the read window. Returns the number of bytes which the
 * remote end may send without overflowing the window limit read_avail (if
 * passed) will be populated with the number of bytes actually available to be
 * read window_size_initial (if passed) will be populated with the
 * window_size_initial as defined by the channel_open request
 */
LIBSSH2_API unsigned long
libssh2_channel_window_read_ex(LIBSSH2_CHANNEL * channel,
                               unsigned long *read_avail,
                               unsigned long *window_size_initial)
{
    if (window_size_initial) {
        *window_size_initial = channel->remote.window_size_initial;
    }

    if (read_avail) {
        unsigned long bytes_queued = 0;
        LIBSSH2_PACKET *packet =
            _libssh2_list_first(&channel->session->packets);

        while (packet) {
            unsigned char packet_type = packet->data[0];

            if (((packet_type == SSH_MSG_CHANNEL_DATA)
                 || (packet_type == SSH_MSG_CHANNEL_EXTENDED_DATA))
                && (_libssh2_ntohu32(packet->data + 1) == channel->local.id)) {
                bytes_queued += packet->data_len - packet->data_head;
            }

            packet = _libssh2_list_next(&packet->node);
        }

        *read_avail = bytes_queued;
    }

    return channel->remote.window_size;
}

/*
 * libssh2_channel_window_write_ex
 *
 * Check the status of the write window Returns the number of bytes which may
 * be safely writen on the channel without blocking window_size_initial (if
 * passed) will be populated with the size of the initial window as defined by
 * the channel_open request
 */
LIBSSH2_API unsigned long
libssh2_channel_window_write_ex(LIBSSH2_CHANNEL * channel,
                                unsigned long *window_size_initial)
{
    if (window_size_initial) {
        /* For locally initiated channels this is very often 0, so it's not
         * *that* useful as information goes */
        *window_size_initial = channel->local.window_size_initial;
    }

    return channel->local.window_size;
}
