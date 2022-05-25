/*
 * BSD 3-Clause License
 *
 * Copyright (c) 2019, Analog Devices, Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. Neither the name of the copyright holder nor the names of its
 *    contributors may be used to endorse or promote products derived from
 *    this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#include "../include/cuda_utils.h"
#include <iostream>
namespace aditof {};

// -------------------      CUDA        -----------------------------------------------

__global__ void buildDistortionCorrectionCacheCuda(double *m_distortion_cache_d,
                                                   double *m_parameters_d) {

    int threadPosition = blockIdx.x * THREAD_PER_BLOCK + threadIdx.x;

    int i = threadPosition % (int)m_parameters_d[0];
    int j = threadPosition / (int)m_parameters_d[0];

    if (i >= 0 && i < m_parameters_d[0]) {
        if (j >= 0 && j < m_parameters_d[1]) {
            double x = (i - m_parameters_d[4]) / m_parameters_d[2];
            double y = (j - m_parameters_d[5]) / m_parameters_d[3];

            double r2 = x * x + y * y;
            double k_calc = double(1 + m_parameters_d[6] * r2 +
                                   m_parameters_d[7] * r2 * r2 +
                                   m_parameters_d[8] * r2 * r2 * r2);
            m_distortion_cache_d[j * (int)m_parameters_d[0] + i] = k_calc;
        }
    }
}

__global__ void
applyDistortionCorrectionCacheCuda(uint16_t *m_frame_d, uint16_t *tmp_frame,
                                   double *m_parameters_d,
                                   double *m_distortion_cache_d) {

    int threadPosition = blockIdx.x * THREAD_PER_BLOCK + threadIdx.x;

    int i = threadPosition % (int)m_parameters_d[0];
    int j = threadPosition / (int)m_parameters_d[0];

    if (i >= 0 && i < m_parameters_d[0]) {
        if (j >= 0 && j < m_parameters_d[1]) {

            double x = (double(i) - m_parameters_d[4]) / m_parameters_d[2];
            double y = (double(j) - m_parameters_d[5]) / m_parameters_d[3];

            //apply correction
            double x_dist_adim =
                x * m_distortion_cache_d[j * (int)m_parameters_d[0] + i];
            double y_dist_adim =
                y * m_distortion_cache_d[j * (int)m_parameters_d[0] + i];

            //back to original space
            int x_dist =
                (int)(x_dist_adim * m_parameters_d[2] + m_parameters_d[4]);
            int y_dist =
                (int)(y_dist_adim * m_parameters_d[3] + m_parameters_d[5]);

            if (x_dist >= 0 && x_dist < (int)m_parameters_d[0] && y_dist >= 0 &&
                y_dist < (int)m_parameters_d[1]) {
                m_frame_d[j * (int)m_parameters_d[0] + i] =
                    tmp_frame[y_dist * (int)m_parameters_d[0] + x_dist];
            } else {
                m_frame_d[j * (int)m_parameters_d[0] + i] =
                    tmp_frame[j * (int)m_parameters_d[0] + i];
            }
        }
    }
}

__global__ void buildGeometryCorrectionCacheCuda(double *m_geometry_cache_d,
                                                 double *m_parameters_d) {

    int threadPosition = blockIdx.x * THREAD_PER_BLOCK + threadIdx.x;

    int i = threadPosition / (int)m_parameters_d[0];
    int j = threadPosition % (int)m_parameters_d[0];

    if (i >= 0 && i < m_parameters_d[1]) {
        if (j >= 0 && j < m_parameters_d[0]) {
            double tanXAngle = (m_parameters_d[9] - j) / m_parameters_d[2];
            double tanYAngle = (m_parameters_d[10] - i) / m_parameters_d[3];

            m_geometry_cache_d[i * (int)m_parameters_d[0] + j] =
                1.0 / sqrt(1 + tanXAngle * tanXAngle + tanYAngle * tanYAngle);
        }
    }
}

__global__ void applyGeometryCorrectionCacheCuda(uint16_t *m_frame_d,
                                                 double *m_parameters_d,
                                                 double *m_geometry_cache_d

) {
    int threadPosition = blockIdx.x * THREAD_PER_BLOCK + threadIdx.x;

    if (threadPosition >= 0 &&
        threadPosition < m_parameters_d[0] * m_parameters_d[1]) {
        if (m_frame_d[threadPosition] > m_parameters_d[14])
            m_frame_d[threadPosition] = m_parameters_d[14];
        else
            m_frame_d[threadPosition] =
                m_frame_d[threadPosition] * m_geometry_cache_d[threadPosition];
    }
}

__global__ void buildDepthCorrectionCacheCuda(uint16_t *m_depth_cache_d,
                                              double *m_parameters_d) {

    int threadPosition = blockIdx.x * THREAD_PER_BLOCK + threadIdx.x;
    if (threadPosition < m_parameters_d[13]) {
        int16_t currentValue = static_cast<int16_t>(
            static_cast<float>(threadPosition) * m_parameters_d[11] +
            m_parameters_d[12]);
        m_depth_cache_d[threadPosition] = currentValue <= m_parameters_d[14]
                                              ? currentValue
                                              : m_parameters_d[14];
    }
}

__global__ void applyDepthCorrectionCacheCuda(uint16_t *m_frame_d,
                                              double *m_parameters_d,
                                              uint16_t *m_depth_cache_d) {

    int threadPosition = blockIdx.x * THREAD_PER_BLOCK + threadIdx.x;

    if (threadPosition >= 0 &&
        threadPosition < m_parameters_d[0] * m_parameters_d[1]) {
        *(m_frame_d + threadPosition) =
            *(m_depth_cache_d + *(m_frame_d + threadPosition));
    }
}

//--------------------------    CLASS   -------------------------------------------------------------

void cudaOnTarget::buildDistortionCorrectionCache() {

    std::cout << "CUDA_CXX: Building Distortion correction\n";

    cudaMalloc((void **)&m_distortion_cache_d,
               sizeof(double) * m_parameters[0] * m_parameters[1]);

    buildDistortionCorrectionCacheCuda<<<m_parameters[0] * m_parameters[1] /
                                             THREAD_PER_BLOCK,
                                         THREAD_PER_BLOCK>>>(
        m_distortion_cache_d, m_parameters_d);

    // m_distortion_cache =
    //     (double *)malloc(sizeof(double) * m_parameters[0] * m_parameters[1]);
    // cudaMemcpy(m_distortion_cache, m_distortion_cache_d,
    //            sizeof(double) * m_parameters[0] * m_parameters[1],
    //            cudaMemcpyDeviceToHost);

    // std::cout << "GPU distortion: \n";
    // for (int i = 0; i < 10; i++) {
    //     std::cout << m_distortion_cache[i] << ", ";
    // }
    // std::cout << "\n\n\n";
}

void cudaOnTarget::buildGeometryCorrectionCache() {

    std::cout << "CUDA_CXX: Building Geometry correction\n";

    cudaMalloc((void **)&m_geometry_cache_d,
               sizeof(double) * m_parameters[0] * m_parameters[1]);

    //Check if more blocks nedded than resulted from division
    int nrOfBlocks =
        ((m_parameters[0] * m_parameters[1] / THREAD_PER_BLOCK) *
             THREAD_PER_BLOCK <
         m_parameters[0] * m_parameters[1])
            ? m_parameters[0] * m_parameters[1] / THREAD_PER_BLOCK + 1
            : m_parameters[0] * m_parameters[1] / THREAD_PER_BLOCK;
    buildGeometryCorrectionCacheCuda<<<nrOfBlocks, THREAD_PER_BLOCK>>>(
        m_geometry_cache_d, m_parameters_d);

    // m_geometry_cache =
    //     (double *)malloc(sizeof(double) * m_parameters[0] * m_parameters[1]);
    // cudaMemcpy(m_geometry_cache, m_geometry_cache_d,
    //            sizeof(double) * m_parameters[0] * m_parameters[1],
    //            cudaMemcpyDeviceToHost);

    // std::cout << "GPU geometry: \n";
    // for (int i = 0; i < 10; i++) {
    //     std::cout << m_geometry_cache[i] << ", ";
    // }
    // std::cout << "\n\n\n";
}

void cudaOnTarget::buildDepthCorrectionCache() {

    std::cout << "CUDA_CXX: Building Depth correction\n";

    cudaMalloc((void **)&m_depth_cache_d, sizeof(uint16_t) * m_parameters[13]);

    //Check if more blocks nedded than resulted from division
    int nrOfBlocks = ((m_parameters[13] / THREAD_PER_BLOCK) * THREAD_PER_BLOCK <
                      m_parameters[13])
                         ? m_parameters[13] / THREAD_PER_BLOCK + 1
                         : m_parameters[13] / THREAD_PER_BLOCK;
    buildDepthCorrectionCacheCuda<<<nrOfBlocks, THREAD_PER_BLOCK>>>(
        m_depth_cache_d, m_parameters_d);

    // m_depth_cache = (uint16_t *)malloc(sizeof(uint16_t) * m_parameters[13]);
    // cudaMemcpy(m_depth_cache, m_depth_cache_d,
    //    sizeof(uint16_t) * m_parameters[13], cudaMemcpyDeviceToHost);

    // std::cout << "GPU depth: \n";
    // for (int i = 0; i < 10; i++) {
    //     std::cout << m_depth_cache[i] << ", ";
    // }
    // std::cout << "\n\n\n";
}

void cudaOnTarget::applyDistortionCorrection() {

    //create temporary frame buffer
    uint16_t *tmp_frame;
    cudaMalloc((void **)&tmp_frame,
               sizeof(uint16_t) * m_parameters[0] * m_parameters[1]);
    cudaMemcpy(tmp_frame, m_frame_d,
               sizeof(uint16_t) * m_parameters[0] * m_parameters[1],
               cudaMemcpyDeviceToDevice);

    //Check if more blocks nedded than resulted from division
    int nrOfBlocks =
        ((m_parameters[0] * m_parameters[1] / THREAD_PER_BLOCK) *
             THREAD_PER_BLOCK <
         m_parameters[0] * m_parameters[1])
            ? m_parameters[0] * m_parameters[1] / THREAD_PER_BLOCK + 1
            : m_parameters[0] * m_parameters[1] / THREAD_PER_BLOCK;
    applyDistortionCorrectionCacheCuda<<<nrOfBlocks, THREAD_PER_BLOCK>>>(
        m_frame_d, tmp_frame, m_parameters_d, m_distortion_cache_d);
    cudaFree(tmp_frame);
}
void cudaOnTarget::applyDepthCorrection() {

    //Check if more blocks nedded than resulted from division
    int nrOfBlocks =
        ((m_parameters[0] * m_parameters[1] / THREAD_PER_BLOCK) *
             THREAD_PER_BLOCK <
         m_parameters[0] * m_parameters[1])
            ? m_parameters[0] * m_parameters[1] / THREAD_PER_BLOCK + 1
            : m_parameters[0] * m_parameters[1] / THREAD_PER_BLOCK;
    applyDepthCorrectionCacheCuda<<<nrOfBlocks, THREAD_PER_BLOCK>>>(
        m_frame_d, m_parameters_d, m_depth_cache_d);
}

void cudaOnTarget::applyGeometryCorrection() {
    //Check if more blocks nedded than resulted from division
    int nrOfBlocks =
        ((m_parameters[0] * m_parameters[1] / THREAD_PER_BLOCK) *
             THREAD_PER_BLOCK <
         m_parameters[0] * m_parameters[1])
            ? m_parameters[0] * m_parameters[1] / THREAD_PER_BLOCK + 1
            : m_parameters[0] * m_parameters[1] / THREAD_PER_BLOCK;
    applyGeometryCorrectionCacheCuda<<<nrOfBlocks, THREAD_PER_BLOCK>>>(
        m_frame_d, m_parameters_d, m_geometry_cache_d);
}

void cudaOnTarget::cpyFrameToGPU(uint16_t *frame) {
    cudaMemcpy(m_frame_d, frame,
               sizeof(uint16_t) * m_parameters[0] * m_parameters[1],
               cudaMemcpyHostToDevice);
}
void cudaOnTarget::cpyFrameFromGPU(uint16_t *frame) {
    cudaMemcpy(frame, m_frame_d,
               sizeof(uint16_t) * m_parameters[0] * m_parameters[1],
               cudaMemcpyDeviceToHost);
}

void cudaOnTarget::printFrameFromGPU() {
    cpyFrameFromGPU(m_frame);
    for (int i = 0; i < 10; i++) {
        std::cout << m_frame[i] << ", ";
    }
}

void cudaOnTarget::setParameters(double width, double height, double fx,
                                 double fy, double cx, double cy, double k1,
                                 double k2, double k3, double x0, double y0,
                                 double gain, double offset,
                                 double pixelMaxValue, double range) {
    //Moving parameters on GPU memory
    double parameters[15] = {width, height, fx, fy, cx,   cy,     k1,
                             k2,    k3,     x0, y0, gain, offset, pixelMaxValue,
                             range};
    m_parameters = (double *)malloc(15 * sizeof(double));
    memcpy(m_parameters, parameters, 15 * sizeof(double));

    cudaMalloc((void **)&m_parameters_d, sizeof(double) * 15);
    cudaMemcpy(m_parameters_d, parameters, sizeof(double) * 15,
               cudaMemcpyHostToDevice);

    //allocating memory for frame
    cudaMalloc((void **)&m_frame_d, sizeof(uint16_t) * width * height);
    m_frame = (uint16_t *)malloc(sizeof(uint16_t) * width * height);

    //load neural network model
    loadNetworkModel();
}

void cudaOnTarget::freeAll() {
    cudaFree(m_geometry_cache_d);
    cudaFree(m_distortion_cache_d);
    cudaFree(m_depth_cache_d);
    cudaFree(m_frame_d);
    cudaFree(m_parameters_d);
}

std::string cudaOnTarget::getFileNameWeights(std::string fileName) {
    std::string firstPart = PATH_TO_CNN_JSON;
    std::string lastPartWeights = "_weights.txt";

    return (firstPart.append(fileName.append(lastPartWeights)));
}
std::string cudaOnTarget::getFileNameBias(std::string fileName) {
    std::string firstPart = PATH_TO_CNN_JSON;
    std::string lastPartBias = "_bias.txt";

    return (firstPart.append(fileName.append(lastPartBias)));
}

void cudaOnTarget::readInLayer(std::vector<Layer> &network,
                               std::string fileName) {
    std::string fileNameWeights = getFileNameWeights(fileName);
    std::string fileNameBias = getFileNameBias(fileName);

    std::ifstream myFileWeights; // creates stream myFile
    std::ifstream myFileBias;    // creates stream myFile

    myFileWeights.open(fileNameWeights); // opens .txt file
    myFileBias.open(fileNameBias);       // opens .txt file
    if (!myFileWeights.is_open() ||
        !myFileBias.is_open()) // check file is open, quit if not
    {
        std::cerr << "failed to open file\n";
        return;
    }

    std::vector<double> weights; // vector to store the numerical values in
    std::vector<double> bias;    // vector to store the numerical values in

    double number = 0;
    while (myFileWeights >> number) {
        weights.push_back(number);
    }
    while (myFileBias >> number) {
        bias.push_back(number);
    }

    Layer layer;
    layer.name = fileName;
    layer.weights = weights;
    layer.bias = bias;

    network.push_back(layer);

    std::cout << "########\nWeights: " << weights.size()
              << "\nBiases: " << bias.size() << std::endl;
}

void cudaOnTarget::loadNetworkModel() {

    readInLayer(Network, "layer_0");
    readInLayer(Network, "layer_1");
    readInLayer(Network, "layer_2");
    readInLayer(Network, "layer_3");

    cpyNetworkToGPU();
}

void cudaOnTarget::cpyNetworkToGPU() {
    if (Network.size()==0) {
        std::cout << "CUDA_CXX: Please load the model first!\n";
        return;
    }
    else
    {
        int size_tmp =1;
        size_tmp += Network.size();
        for(int i=0;i<Network.size();i++)
        {
            size_tmp += Network[i].weights.size();
            size_tmp += Network[i].bias.size();
        }
    }
    cudaMalloc((void **)&network_d, sizeof(double) * size_tmp);
    


}