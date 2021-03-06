// Modifications copyright (C) 2017, Baidu.com, Inc.
// Copyright 2017 The Apache Software Foundation

// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

package com.baidu.palo.analysis;

import com.baidu.palo.catalog.Column;
import com.baidu.palo.catalog.PartitionInfo;
import com.baidu.palo.catalog.PartitionType;
import com.baidu.palo.catalog.PrimitiveType;
import com.baidu.palo.catalog.RangePartitionInfo;
import com.baidu.palo.common.AnalysisException;
import com.baidu.palo.common.DdlException;
import com.baidu.palo.common.io.Text;

import com.google.common.collect.Lists;
import com.google.common.collect.Maps;
import com.google.common.collect.Sets;

import java.io.DataInput;
import java.io.DataOutput;
import java.io.IOException;
import java.util.List;
import java.util.Map;
import java.util.Set;

// to describe the key range partition's information in create table stmt
public class RangePartitionDesc extends PartitionDesc {
    private List<String> partitionColNames;
    private List<SingleRangePartitionDesc> singleRangePartitionDescs;

    public RangePartitionDesc() {
        type = PartitionType.RANGE;
        partitionColNames = Lists.newArrayList();
        singleRangePartitionDescs = Lists.newArrayList();
    }

    public RangePartitionDesc(List<String> partitionColNames,
                              List<SingleRangePartitionDesc> singlePartitionDescs) {
        type = PartitionType.RANGE;
        this.partitionColNames = partitionColNames;
        this.singleRangePartitionDescs = singlePartitionDescs;
        if (singleRangePartitionDescs == null) {
            singleRangePartitionDescs = Lists.newArrayList();
        }
    }

    public List<SingleRangePartitionDesc> getSingleRangePartitionDescs() {
        return this.singleRangePartitionDescs;
    }

    public List<String> getPartitionColNames() {
        return partitionColNames;
    }

    @Override
    public void analyze(Set<String> cols, Map<String, String> otherProperties) throws AnalysisException {
        if (partitionColNames == null || partitionColNames.isEmpty()) {
            throw new AnalysisException("No partition columns.");
        }

        if (partitionColNames.size() != 1) {
            throw new AnalysisException("Only allow partitioned by one column");
        }

        for (String partitionCol : partitionColNames) {
            // use this to infer user which columns not exist
            if (!cols.contains(partitionCol)) {
                throw new AnalysisException("Partition column[" + partitionCol + "] does not exist.");
            }
            
            if (partitionCol.equals(PrimitiveType.HLL.toString())) {
                throw new AnalysisException("Partition column[" + partitionCol + "] can't be HLL.");
            }
        }

        Set<String> nameSet = Sets.newTreeSet(String.CASE_INSENSITIVE_ORDER);
        for (SingleRangePartitionDesc desc : singleRangePartitionDescs) {
            if (nameSet.contains(desc.getPartitionName())) {
                throw new AnalysisException("Duplicated partition name: " + desc.getPartitionName());
            }
            // in create table stmt, we use given properties
            // copy one. because ProperAnalyzer will remove entry after analyze
            Map<String, String> givenProperties = null;
            if (otherProperties != null) {
                givenProperties = Maps.newHashMap(otherProperties);
            }
            desc.analyze(cols.size(), givenProperties);
            nameSet.add(desc.getPartitionName());
        }
    }

    @Override
    public String toSql() {
        StringBuilder sb = new StringBuilder();
        sb.append("PARTITION BY RANGE(");
        int idx = 0;
        for (String column : partitionColNames) {
            if (idx != 0) {
                sb.append(", ");
            }
            sb.append("`").append(column).append("`");
            idx++;
        }
        sb.append(")\n(\n");
        
        for (int i = 0; i < singleRangePartitionDescs.size(); i++) {
            if (i != 0) {
                sb.append(",\n");
            }
            sb.append(singleRangePartitionDescs.get(i).toSql());
        }
        sb.append("\n)");
        return sb.toString();
    }

    @Override
    public String toString() {
        return toSql();
    }

    @Override
    public PartitionInfo toPartitionInfo(List<Column> schema, Map<String, Long> partitionNameToId) throws DdlException {
        List<Column> partitionColumns = Lists.newArrayList();

        // check and get partition column
        for (String colName : partitionColNames) {
            boolean find = false;
            for (Column column : schema) {
                if (column.getName().equalsIgnoreCase(colName)) {
                    if (!column.isKey()) {
                        throw new DdlException("Partition column[" + colName + "] is not key column");
                    }
                    try {
                        RangePartitionInfo.checkRangeColumnType(column);
                    } catch (AnalysisException e) {
                        throw new DdlException(e.getMessage());
                    }

                    partitionColumns.add(column);
                    find = true;
                    break;
                }
            }
            if (!find) {
                throw new DdlException("Partition column[" + colName + "] does not found");
            }
        }

        /*
         * validate key range
         * eg.
         * VALUE LESS THEN (10, 100, 1000)
         * VALUE LESS THEN (50, 500)
         * VALUE LESS THEN (80)
         * 
         * key range is:
         * ( {MIN, MIN, MIN},    {10,  100, 1000} )
         * [ {10,  100, 500},    {50,  500, ?   } )
         * [ {50,  500, ?  },    {80,  ?,   ?   } )
         */
        RangePartitionInfo rangePartitionInfo = new RangePartitionInfo(partitionColumns);
        for (SingleRangePartitionDesc desc : singleRangePartitionDescs) {
            long partitionId = partitionNameToId.get(desc.getPartitionName());
            rangePartitionInfo.handleNewSinglePartitionDesc(desc, partitionId);
        }
        return rangePartitionInfo;
    }

    @Override
    public void write(DataOutput out) throws IOException {
        super.write(out);

        int count = partitionColNames.size();
        out.writeInt(count);
        for (String colName : partitionColNames) {
            Text.writeString(out, colName);
        }

        count = singleRangePartitionDescs.size();
        out.writeInt(count);
        for (SingleRangePartitionDesc singleRangePartitionDesc : singleRangePartitionDescs) {
            singleRangePartitionDesc.write(out);
        }
    }

    @Override
    public void readFields(DataInput in) throws IOException {
        int count = in.readInt();
        for (int i = 0; i < count; i++) {
            partitionColNames.add(Text.readString(in));
        }

        count = in.readInt();
        for (int i = 0; i < count; i++) {
            SingleRangePartitionDesc desc = new SingleRangePartitionDesc();
            desc.readFields(in);
            singleRangePartitionDescs.add(desc);
        }
    }
}
