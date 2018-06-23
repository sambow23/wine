/*
 * DirectShow ASF DLL
 *
 * Copyright (C) 2018 Zebediah Figura
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA
 */

#include "windef.h"
#define COBJMACROS
#include "strmif.h"
#include "wine/strmbase.h"
#include "dmodshow.h"
#include "qasf_private.h"

#include "wine/debug.h"


WINE_DEFAULT_DEBUG_CHANNEL(qasf);

static const WCHAR DMOWrapperFilterW[] = {'D','M','O',' ','W','r','a','p','p','e','r',' ','F','i','l','t','e','r',0};

FactoryTemplate const g_Templates[] = {
    {
        DMOWrapperFilterW,
        &CLSID_DMOWrapperFilter,
        create_DMOWrapperFilter,
        NULL
    },
};

int g_cTemplates = sizeof(g_Templates) / sizeof(g_Templates[0]);

/***********************************************************************
 *    DllMain (QASF.@)
 */
BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, void *reserved)
{
    return STRMBASE_DllMain(instance, reason, reserved);
}

/***********************************************************************
 *    DllGetClassObject (QASF.@)
 */
HRESULT WINAPI DllGetClassObject(REFCLSID clsid, REFIID iid, void **obj)
{
    return STRMBASE_DllGetClassObject(clsid, iid, obj);
}

/***********************************************************************
 *    DllRegisterServer (QASF.@)
 */
HRESULT WINAPI DllRegisterServer(void)
{
    TRACE("()\n");
    return AMovieDllRegisterServer2(TRUE);
}

/***********************************************************************
 *    DllUnregisterServer (QASF.@)
 */
HRESULT WINAPI DllUnregisterServer(void)
{
    TRACE("\n");
    return AMovieDllRegisterServer2(FALSE);
}

/***********************************************************************
 *    DllCanUnloadNow (QASF.@)
 */
HRESULT WINAPI DllCanUnloadNow(void)
{
    TRACE("\n");
    return STRMBASE_DllCanUnloadNow();
}
