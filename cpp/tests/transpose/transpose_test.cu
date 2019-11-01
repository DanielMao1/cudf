/*
 * Copyright (c) 2019, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#include <cudf/transpose.hpp>
#include <tests/utilities/base_fixture.hpp>
#include <tests/utilities/type_lists.hpp>
#include <tests/utilities/column_utilities.hpp>
#include <tests/utilities/column_wrapper.hpp>

#include <limits>
#include <random>
#include <algorithm>

namespace {

using cudf::test::fixed_width_column_wrapper;

template <typename T, typename F>
auto generate_vectors(size_t ncols, size_t nrows, F generator)
{
  std::vector<std::vector<T>> values;

  values.resize(ncols);
  for (auto& value_col : values) {
    value_col.resize(nrows);
    std::generate(value_col.begin(), value_col.end(), generator);
  }

  return values;
}

template <typename T>
auto transpose_vectors(std::vector<std::vector<T>> const& input)
{
  if (input.empty()) {
    return input;
  }
  size_t nrows = input.front().size();

  std::vector<std::vector<T>> transposed(nrows);
  for (auto& col : transposed) {
    col.resize(input.size());
  }

  for (size_t col = 0; col < input.size(); ++col) {
    for (size_t row = 0; row < nrows; ++row) {
      transposed[row][col] = input[col][row];
    }
  }

  return transposed;
}

template <typename T>
auto make_columns(std::vector<std::vector<T>> const& values)
{
  std::vector<fixed_width_column_wrapper<T>> columns;

  for (auto const& value_col : values) {
    columns.emplace_back(value_col.begin(), value_col.end());
  }

  return columns;
}

template <typename T>
auto make_columns(std::vector<std::vector<T>> const& values,
  std::vector<std::vector<bool>> const& valids)
{
  std::vector<fixed_width_column_wrapper<T>> columns;

  for (size_t col = 0; col < values.size(); ++col) {
    columns.emplace_back(values[col].begin(), values[col].end(), valids[col].begin());
  }

  return columns;
}

template <typename T>
auto make_table_view(std::vector<fixed_width_column_wrapper<T>> const& cols)
{
  std::vector<cudf::column_view> views;
  for (auto const& col : cols) {
    views.push_back(col);
  }

  return cudf::table_view(views);
}

template <typename T>
void run_test(size_t ncols, size_t nrows, bool add_nulls)
{
  std::mt19937 rng(1);

  // Generate values as vector of vectors
  auto const values = generate_vectors<T>(ncols, nrows, [&rng]() { 
    return static_cast<T>(rng());
  });
  auto const valuesT = transpose_vectors(values);

  std::vector<fixed_width_column_wrapper<T>> input_cols;
  std::vector<fixed_width_column_wrapper<T>> expected_cols;

  if (add_nulls) {
    // Generate null mask as vector of vectors
    auto const valids = generate_vectors<bool>(ncols, nrows, [&rng]() {
      return static_cast<bool>(rng() % 3 > 0);
    });
    auto const validsT = transpose_vectors(valids);

    // Create column wrappers from vector of vectors
    input_cols = make_columns(values, valids);
    expected_cols = make_columns(valuesT, validsT);
  } else {
    input_cols = make_columns(values);
    expected_cols = make_columns(valuesT);
  }

  // Create table views from column wrappers
  auto input_view = make_table_view(input_cols);
  auto expected_view = make_table_view(expected_cols);

  auto result = transpose(input_view);
  auto result_view = result->view();

  CUDF_EXPECTS(result_view.num_columns() == expected_view.num_columns(), "Expected same number of columns");
  for (cudf::size_type i = 0; i < result_view.num_columns(); ++i) {
    cudf::test::expect_columns_equal(result_view.column(i), expected_view.column(i));
  }
}

}  // namespace

template <typename T>
class TransposeTest : public cudf::test::BaseFixture {};

TYPED_TEST_CASE(TransposeTest, cudf::test::FixedWidthTypes);

TYPED_TEST(TransposeTest, SingleValue)
{
  run_test<TypeParam>(1, 1, false);
}

TYPED_TEST(TransposeTest, SingleColumn)
{
  run_test<TypeParam>(1, 1000, false);
}

TYPED_TEST(TransposeTest, SingleColumnNulls)
{
  run_test<TypeParam>(1, 1000, true);
}

TYPED_TEST(TransposeTest, Square)
{
  run_test<TypeParam>(100, 100, false);
}

TYPED_TEST(TransposeTest, SquareNulls)
{
  run_test<TypeParam>(100, 100, true);
}

TYPED_TEST(TransposeTest, Slim)
{
  run_test<TypeParam>(10, 1000, false);
}

TYPED_TEST(TransposeTest, SlimNulls)
{
  run_test<TypeParam>(10, 1000, true);
}

TYPED_TEST(TransposeTest, Fat)
{
  run_test<TypeParam>(1000, 10, false);
}

TYPED_TEST(TransposeTest, FatNulls)
{
  run_test<TypeParam>(1000, 10, true);
}

TYPED_TEST(TransposeTest, EmptyTable)
{
  run_test<TypeParam>(0, 0, false);
}

TYPED_TEST(TransposeTest, EmptyColumns)
{
  run_test<TypeParam>(10, 0, false);
}
