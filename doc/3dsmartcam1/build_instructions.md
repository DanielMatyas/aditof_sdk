# 3D Smart Camera Build Instructions


## Building the SDK only

### SDK dependencies
To build the SDK and run the included applications and example code the following dependencies must be installed in the system:
 - v4l-utils
 - libopencv-dev
 - cmake
 - glog v0.3.5
 - libwebsockets v3.2.3
 - protocol buffers v3.9.0

The camera's Linux image already contains all the SDK dependencies and there's no need to install them again. To update and build the SDK just follow the steps below.

Step 0.
Update time. Else, cmake and many apt packages will not work. To sync time with host computer through ssh use:
```
ssh analog@ip sudo date -s @`( date -u +"%s" )`
```
Update repository:
```
git fetch GIT_SSL_NO_VERIFY=true
```

```console
analog@adi-smart-camera:~/Workspace/aditof_sdk$ git pull
analog@adi-smart-camera:~/Workspace/aditof_sdk$ cd build
# Optionally
analog@adi-smart-camera:~/Workspace/aditof_sdk/build$ cmake -DWITH_EXAMPLES=off -DCMAKE_PREFIX_PATH="/opt/glog;/opt/protobuf;/opt/websockets" ..
analog@adi-smart-camera:~/Workspace/aditof_sdk/build$ cmake -DUSE_3D_SMART=1 ..
analog@adi-smart-camera:~/Workspace/aditof_sdk/build$ make -j4
```
[This page](https://github.com/analogdevicesinc/aditof_sdk/tree/master/cmake/) contains more details about the SDK's CMake build system and the various build options. 
